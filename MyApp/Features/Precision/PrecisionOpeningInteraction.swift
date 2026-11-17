import CoreGraphics
import Foundation

struct PrecisionOpeningHitTarget: Sendable {
    let openingID: UUID
    let start: CGPoint
    let end: CGPoint
    let labelBounds: CGRect?
}

enum PrecisionOpeningHitTesting {
    static let segmentTolerance: CGFloat = 22

    static func selectedOpening(
        at point: CGPoint,
        targets: [PrecisionOpeningHitTarget]
    ) -> UUID? {
        if let label = targets.first(where: { $0.labelBounds?.insetBy(dx: -8, dy: -8).contains(point) == true }) {
            return label.openingID
        }
        return targets.compactMap { target -> (UUID, CGFloat)? in
            let distance = distanceFromPoint(point, toSegmentFrom: target.start, to: target.end)
            return distance <= segmentTolerance ? (target.openingID, distance) : nil
        }
        .min { $0.1 < $1.1 }?.0
    }

    static func targets(
        for plan: ParametricFloorPlan,
        transform: CGAffineTransform,
        selectedOpeningID: UUID? = nil
    ) -> [PrecisionOpeningHitTarget] {
        let vertices = Dictionary(uniqueKeysWithValues: plan.vertices.map { ($0.id, $0.position) })
        let walls = Dictionary(uniqueKeysWithValues: plan.walls.map { ($0.id, $0) })
        return plan.openings.compactMap { opening in
            guard let wall = walls[opening.hostWallID],
                  let wallStart = vertices[wall.startVertexID],
                  let wallEnd = vertices[wall.endVertexID],
                  let width = opening.width?.value else { return nil }
            let wallLength = wallStart.distance(to: wallEnd)
            guard wallLength.isFinite, wallLength > 0, width.isFinite, width > 0 else { return nil }
            let center: Double
            switch opening.horizontalAnchor {
            case .distanceFromStart(let measurement): center = measurement.value
            }
            let lower = max(0, center - width / 2)
            let upper = min(wallLength, center + width / 2)
            guard upper > lower else { return nil }
            let dx = (wallEnd.x - wallStart.x) / wallLength
            let dy = (wallEnd.y - wallStart.y) / wallLength
            let start = CGPoint(x: wallStart.x + dx * lower, y: wallStart.y + dy * lower).applying(transform)
            let end = CGPoint(x: wallStart.x + dx * upper, y: wallStart.y + dy * upper).applying(transform)
            let labelBounds: CGRect? = opening.id == selectedOpeningID
                ? CGRect(x: (start.x + end.x) / 2 - 42, y: (start.y + end.y) / 2 - 30, width: 84, height: 24)
                : nil
            return PrecisionOpeningHitTarget(openingID: opening.id, start: start, end: end, labelBounds: labelBounds)
        }
    }

    private static func distanceFromPoint(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let squaredLength = dx * dx + dy * dy
        guard squaredLength > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let projection = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / squaredLength, 0), 1)
        return hypot(point.x - (start.x + projection * dx), point.y - (start.y + projection * dy))
    }
}

struct OpeningMeasurementDraft: Equatable, Sendable {
    struct Values: Equatable, Sendable {
        var referenceEndpoint: OpeningReferenceEndpoint?
        var startOffsetMillimeters: String
        var endOffsetMillimeters: String
        var widthMillimeters: String
        var heightMillimeters: String
        var lowerElevationMillimeters: String
        var topElevationMillimeters: String
    }

    let openingID: UUID
    let original: Values
    var referenceEndpoint: OpeningReferenceEndpoint?
    var startOffsetMillimeters: String
    var endOffsetMillimeters: String
    var widthMillimeters: String
    var heightMillimeters: String
    var lowerElevationMillimeters: String
    var topElevationMillimeters: String
    var laserVerified: Bool

    var current: Values {
        Values(
            referenceEndpoint: referenceEndpoint,
            startOffsetMillimeters: startOffsetMillimeters,
            endOffsetMillimeters: endOffsetMillimeters,
            widthMillimeters: widthMillimeters,
            heightMillimeters: heightMillimeters,
            lowerElevationMillimeters: lowerElevationMillimeters,
            topElevationMillimeters: topElevationMillimeters
        )
    }

    var hasChanges: Bool { current != original }

    var offsetChanged: Bool {
        referenceEndpoint != original.referenceEndpoint
            || startOffsetMillimeters != original.startOffsetMillimeters
            || endOffsetMillimeters != original.endOffsetMillimeters
    }

    var requiresReferenceForChanges: Bool { offsetChanged && referenceEndpoint == nil }

    static func make(opening: WallOpening, plan: ParametricFloorPlan) -> OpeningMeasurementDraft {
        let measurements = opening.architecturalMetadata?.measurements ?? []
        let resolution = OpeningMeasurementResolver().resolve(plan: plan)
        let placement = resolution.placements.first { $0.openingID == opening.id }
        func value(_ kind: OpeningMeasurementKind, fallback: Double?) -> String {
            let measured = measurements.filter { $0.kind == kind && $0.value.provenance.source != .derived }
                .max { ($0.value.provenance.timestamp ?? .distantPast) < ($1.value.provenance.timestamp ?? .distantPast) }
            return PrecisionMeasurementInput.millimeters(fromMeters: measured?.value.value ?? fallback)
        }
        let reference = measurements.first(where: {
            ($0.kind == .offsetFromStart || $0.kind == .offsetFromEnd) && $0.reference?.reliability == .verified
        })?.reference?.endpoint
        let initial = Values(
            referenceEndpoint: reference,
            startOffsetMillimeters: value(.offsetFromStart, fallback: placement?.startOffset),
            endOffsetMillimeters: value(.offsetFromEnd, fallback: placement?.endOffset),
            widthMillimeters: value(.width, fallback: placement?.width ?? opening.width?.value),
            heightMillimeters: value(.height, fallback: placement?.height ?? opening.height?.value),
            lowerElevationMillimeters: value(
                opening.kind == .window ? .sillElevation : .thresholdElevation,
                fallback: placement?.lowerElevation ?? opening.verticalOffset?.value
            ),
            topElevationMillimeters: value(.topElevation, fallback: nil)
        )
        return OpeningMeasurementDraft(
            openingID: opening.id,
            original: initial,
            referenceEndpoint: initial.referenceEndpoint,
            startOffsetMillimeters: initial.startOffsetMillimeters,
            endOffsetMillimeters: initial.endOffsetMillimeters,
            widthMillimeters: initial.widthMillimeters,
            heightMillimeters: initial.heightMillimeters,
            lowerElevationMillimeters: initial.lowerElevationMillimeters,
            topElevationMillimeters: initial.topElevationMillimeters,
            laserVerified: false
        )
    }
}

struct OpeningEditPreview: Sendable {
    let candidatePlan: ParametricFloorPlan
    let resolution: OpeningMeasurementResolution
    let validation: GeometryValidationResult

    var isValid: Bool { resolution.isValid && validation.isValid }
}

enum OpeningEditEngine {
    static func preview(draft: OpeningMeasurementDraft, in plan: ParametricFloorPlan) -> OpeningEditPreview? {
        guard let index = plan.openings.firstIndex(where: { $0.id == draft.openingID }) else { return nil }
        var candidate = plan
        let opening = candidate.openings[index]
        var measurements = opening.architecturalMetadata?.measurements.filter { $0.value.provenance.source != .derived } ?? []
        let source: GeometrySourceKind = draft.laserVerified ? .laserVerified : .manualEntered
        let status: GeometryVerificationStatus = draft.laserVerified ? .verified : .unverified
        let provenance = MeasurementProvenance(source: source, verificationStatus: status, timestamp: Date(), uncertainty: nil)

        func replace(
            _ kind: OpeningMeasurementKind,
            millimeters: String,
            original: String,
            endpoint: OpeningReferenceEndpoint? = nil
        ) -> Bool {
            guard millimeters != original else { return true }
            guard !millimeters.isEmpty else { return false }
            guard let meters = PrecisionMeasurementInput.meters(fromMillimeters: millimeters) else { return false }
            measurements.removeAll { $0.kind == kind && $0.value.provenance.source != .derived }
            let reference = endpoint.map {
                OpeningMeasurementReference(
                    endpoint: $0,
                    vertexID: plan.wall(id: opening.hostWallID).map { endpoint == .wallStart ? $0.startVertexID : $0.endVertexID },
                    reliability: .verified
                )
            }
            measurements.append(OpeningMeasurement(
                id: UUID(), openingID: opening.id, kind: kind,
                value: LengthMeasurement(value: meters, provenance: provenance),
                reference: reference, relatedConstraintIDs: []
            ))
            return true
        }

        guard replace(.width, millimeters: draft.widthMillimeters, original: draft.original.widthMillimeters),
              replace(.height, millimeters: draft.heightMillimeters, original: draft.original.heightMillimeters),
              replace(opening.kind == .window ? .sillElevation : .thresholdElevation,
                      millimeters: draft.lowerElevationMillimeters,
                      original: draft.original.lowerElevationMillimeters),
              replace(.topElevation, millimeters: draft.topElevationMillimeters,
                      original: draft.original.topElevationMillimeters) else { return nil }
        if draft.offsetChanged && draft.referenceEndpoint == .wallEnd {
            measurements.removeAll { $0.kind == .offsetFromStart && $0.value.provenance.source != .derived }
            guard replace(.offsetFromEnd, millimeters: draft.endOffsetMillimeters,
                          original: draft.referenceEndpoint == draft.original.referenceEndpoint
                              ? draft.original.endOffsetMillimeters : "",
                          endpoint: .wallEnd) else { return nil }
        } else if draft.offsetChanged && draft.referenceEndpoint == .wallStart {
            measurements.removeAll { $0.kind == .offsetFromEnd && $0.value.provenance.source != .derived }
            guard replace(.offsetFromStart, millimeters: draft.startOffsetMillimeters,
                          original: draft.referenceEndpoint == draft.original.referenceEndpoint
                              ? draft.original.startOffsetMillimeters : "",
                          endpoint: .wallStart) else { return nil }
        } else if draft.requiresReferenceForChanges {
            return nil
        }
        candidate.openings[index] = WallOpening(
            id: opening.id, hostWallID: opening.hostWallID, kind: opening.kind,
            width: opening.width, height: opening.height, verticalOffset: opening.verticalOffset,
            horizontalAnchor: opening.horizontalAnchor, source: opening.source,
            architecturalMetadata: OpeningArchitecturalMetadata(
                measurements: measurements,
                completeness: opening.architecturalMetadata?.completeness ?? .partial,
                doorSwing: opening.architecturalMetadata?.doorSwing
            )
        )
        let resolution = OpeningMeasurementResolver().resolve(plan: candidate)
        let validation = ParametricGeometryValidator().validate(resolution.candidatePlan)
        return OpeningEditPreview(candidatePlan: resolution.candidatePlan, resolution: resolution, validation: validation)
    }
}
