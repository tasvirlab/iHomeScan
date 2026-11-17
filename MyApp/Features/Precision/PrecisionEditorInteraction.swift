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
