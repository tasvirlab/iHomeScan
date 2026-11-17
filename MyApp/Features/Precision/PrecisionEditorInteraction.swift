import CoreGraphics
import Foundation

struct PrecisionWallHitTarget: Equatable, Sendable {
    let wallID: UUID
    let start: CGPoint
    let end: CGPoint
}

enum PrecisionWallHitTesting {
    static func selectedWall(
        at point: CGPoint,
        targets: [PrecisionWallHitTarget],
        tolerance: CGFloat = 28
    ) -> UUID? {
        targets.compactMap { target -> (UUID, CGFloat)? in
            let distance = distance(from: point, toStart: target.start, end: target.end)
            guard distance <= tolerance else { return nil }
            return (target.wallID, distance)
        }.min { lhs, rhs in
            if abs(lhs.1 - rhs.1) > 0.5 { return lhs.1 < rhs.1 }
            return lhs.0.uuidString < rhs.0.uuidString
        }?.0
    }

    private static func distance(from point: CGPoint, toStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let squared = dx * dx + dy * dy
        guard squared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let projection = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / squared, 0), 1)
        return hypot(point.x - (start.x + projection * dx), point.y - (start.y + projection * dy))
    }
}

enum PrecisionMeasurementInput {
    static func meters(fromMillimeters text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let millimeters = Double(normalized), millimeters.isFinite, millimeters > 0 else { return nil }
        return millimeters / 1000
    }

    static func millimeters(fromMeters meters: Double?) -> String {
        guard let meters, meters.isFinite, meters > 0 else { return "" }
        return String(Int((meters * 1000).rounded()))
    }
}

enum PrecisionAutomaticAnchor {
    /// Selects the valid solver result that disturbs the existing plan least.
    /// UUID ordering is used only as a stable tie-breaker through the caller's order.
    static func preferred(
        from original: ParametricFloorPlan,
        start: GeometryRevisionSession,
        end: GeometryRevisionSession
    ) -> (WallLengthAnchorStrategy, GeometryRevisionSession) {
        let startCost = displacementCost(from: original, to: start.displayedPlan)
        let endCost = displacementCost(from: original, to: end.displayedPlan)
        return startCost <= endCost ? (.keepStart, start) : (.keepEnd, end)
    }

    private static func displacementCost(from original: ParametricFloorPlan, to candidate: ParametricFloorPlan) -> Double {
        let positions = Dictionary(uniqueKeysWithValues: original.vertices.map { ($0.id, $0.position) })
        return candidate.vertices.reduce(0) { total, vertex in
            guard let old = positions[vertex.id] else { return total + 1_000_000 }
            let dx = vertex.position.x - old.x
            let dy = vertex.position.y - old.y
            return total + dx * dx + dy * dy
        }
    }
}
