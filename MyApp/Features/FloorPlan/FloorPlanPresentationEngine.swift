import CoreGraphics
import Foundation
import simd

/// Presentation-only geometry helpers. They never mutate persisted RoomPlan coordinates.
enum FloorPlanAlignmentEngine {
    struct Result: Equatable {
        let rotation: CGFloat
        let confidence: CGFloat
    }

    static func alignment(for plan: FloorPlan, minimumConfidence: CGFloat = 0.55) -> Result {
        alignment(for: wallSegments(in: plan), minimumConfidence: minimumConfidence)
    }

    static func alignment(for plan: ParametricFloorPlan, minimumConfidence: CGFloat = 0.55) -> Result {
        let vertices = Dictionary(uniqueKeysWithValues: plan.vertices.map { ($0.id, $0.position) })
        let segments = plan.walls.compactMap { wall -> FloorPlan.Segment? in
            guard let start = vertices[wall.startVertexID], let end = vertices[wall.endVertexID] else { return nil }
            return FloorPlan.Segment(start: CGPoint(x: start.x, y: start.y),
                                     end: CGPoint(x: end.x, y: end.y))
        }
        return alignment(for: segments, minimumConfidence: minimumConfidence)
    }

    private static func alignment(for sourceSegments: [FloorPlan.Segment], minimumConfidence: CGFloat) -> Result {
        let segments = sourceSegments.filter { segment in
            let vector = CGVector(dx: segment.end.x - segment.start.x, dy: segment.end.y - segment.start.y)
            return vector.dx.isFinite && vector.dy.isFinite && hypot(vector.dx, vector.dy) >= 0.25
        }
        guard !segments.isEmpty else { return Result(rotation: 0, confidence: 0) }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var total: CGFloat = 0
        for segment in segments {
            let dx = segment.end.x - segment.start.x
            let dy = segment.end.y - segment.start.y
            let length = hypot(dx, dy)
            let angle = atan2(dy, dx)
            // Fourfold symmetry treats horizontal and vertical walls as one architectural axis.
            x += cos(angle * 4) * length
            y += sin(angle * 4) * length
            total += length
        }
        guard total > 0 else { return Result(rotation: 0, confidence: 0) }
        let confidence = hypot(x, y) / total
        guard confidence >= minimumConfidence else { return Result(rotation: 0, confidence: confidence) }
        return Result(rotation: -atan2(y, x) / 4, confidence: confidence)
    }

    static func wallSegments(in plan: FloorPlan) -> [FloorPlan.Segment] {
        if let surfaces = plan.roomPlanMetadata?.surfaces {
            let measured = surfaces.compactMap { surface in
                surface.kind == .wall ? surface.projectedSegment : nil
            }
            if !measured.isEmpty { return measured }
        }
        let outer = plan.outerWalls.flatMap { points in
            zip(points, points.dropFirst()).map { FloorPlan.Segment(start: $0.0, end: $0.1) }
        }
        return outer + plan.innerWalls
    }
}

enum FloorPlanDimensionLayoutEngine {
    struct Annotation: Equatable {
        let sourceIndex: Int
        let lineStart: CGPoint
        let lineEnd: CGPoint
        let wallStart: CGPoint
        let wallEnd: CGPoint
        let labelCenter: CGPoint
        let labelBounds: CGRect
        let value: Double
        /// Screen-space text is deliberately horizontal and therefore always upright.
        let textRotation: CGFloat = 0
    }

    struct Configuration {
        var minimumLengthMeters: Double = 0.35
        var labelHeight: CGFloat = 22
        var horizontalPadding: CGFloat = 8
        var edgeInset: CGFloat = 8
        var collisionPadding: CGFloat = 5
        var offsets: [CGFloat] = [20, 31, 43]
        var maximumLabels: Int = 14
    }

    static func layout(
        dimensions: [FloorPlan.Dimension],
        transform: CGAffineTransform,
        canvasBounds: CGRect,
        planCenter: CGPoint,
        textForValue: (Double) -> String,
        avoiding avoidanceRects: [CGRect] = [],
        configuration: Configuration = Configuration()
    ) -> [Annotation] {
        let safeBounds = canvasBounds.insetBy(dx: configuration.edgeInset, dy: configuration.edgeInset)
        let screenCenter = planCenter.applying(transform)
        let candidates = dimensions.enumerated().filter { index, dimension in
            dimension.value.isFinite && dimension.value >= configuration.minimumLengthMeters &&
            finite(dimension.start) && finite(dimension.end)
        }.sorted { lhs, rhs in
            if lhs.element.value == rhs.element.value { return lhs.offset < rhs.offset }
            return lhs.element.value > rhs.element.value
        }

        var accepted: [Annotation] = []
        for (index, dimension) in candidates where accepted.count < configuration.maximumLabels {
            let wallStart = dimension.start.applying(transform)
            let wallEnd = dimension.end.applying(transform)
            let dx = wallEnd.x - wallStart.x
            let dy = wallEnd.y - wallStart.y
            let screenLength = hypot(dx, dy)
            guard screenLength >= 30 else { continue }

            let midpoint = CGPoint(x: (wallStart.x + wallEnd.x) / 2, y: (wallStart.y + wallEnd.y) / 2)
            var normal = CGVector(dx: -dy / screenLength, dy: dx / screenLength)
            let towardCenter = CGVector(dx: screenCenter.x - midpoint.x, dy: screenCenter.y - midpoint.y)
            if normal.dx * towardCenter.dx + normal.dy * towardCenter.dy > 0 {
                normal = CGVector(dx: -normal.dx, dy: -normal.dy)
            }

            let text = textForValue(dimension.value)
            let labelWidth = max(44, CGFloat(text.count) * 8 + configuration.horizontalPadding * 2)
            let requiredLineLength = min(labelWidth * 0.55, 80)
            guard screenLength >= requiredLineLength else { continue }

            let normals = [normal, CGVector(dx: -normal.dx, dy: -normal.dy)]
            var chosen: Annotation?
            for candidateNormal in normals {
                for distance in configuration.offsets {
                    let displacement = CGVector(dx: candidateNormal.dx * distance, dy: candidateNormal.dy * distance)
                    let lineStart = CGPoint(x: wallStart.x + displacement.dx, y: wallStart.y + displacement.dy)
                    let lineEnd = CGPoint(x: wallEnd.x + displacement.dx, y: wallEnd.y + displacement.dy)
                    let center = CGPoint(x: midpoint.x + displacement.dx, y: midpoint.y + displacement.dy)
                    let bounds = CGRect(x: center.x - labelWidth / 2,
                                        y: center.y - configuration.labelHeight / 2,
                                        width: labelWidth, height: configuration.labelHeight)
                    guard safeBounds.contains(bounds) else { continue }
                    let padded = bounds.insetBy(dx: -configuration.collisionPadding,
                                                dy: -configuration.collisionPadding)
                    guard !accepted.contains(where: { $0.labelBounds.intersects(padded) }) else { continue }
                    guard !avoidanceRects.contains(where: { $0.intersects(padded) }) else { continue }
                    chosen = Annotation(sourceIndex: index, lineStart: lineStart, lineEnd: lineEnd,
                                        wallStart: wallStart, wallEnd: wallEnd, labelCenter: center,
                                        labelBounds: bounds, value: dimension.value)
                    break
                }
                if chosen != nil { break }
            }
            if let chosen { accepted.append(chosen) }
        }
        return accepted.sorted { $0.sourceIndex < $1.sourceIndex }
    }

    private static func finite(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }
}

enum ArchitecturalCameraFraming {
    struct Result: Equatable {
        let target: SIMD3<Float>
        let position: SIMD3<Float>
        let near: Float
        let far: Float
    }

    static func frame(center: SIMD3<Float>, extents: SIMD3<Float>, fieldOfViewDegrees: Float = 50) -> Result? {
        guard center.x.isFinite, center.y.isFinite, center.z.isFinite,
              extents.x.isFinite, extents.y.isFinite, extents.z.isFinite else { return nil }
        let radius = max(max(extents.x, extents.y), extents.z) / 2
        guard radius > 0 else { return nil }
        let halfFOV = max(fieldOfViewDegrees, 10) * .pi / 360
        let distance = max(radius / tan(halfFOV) * 1.35, 0.75)
        let direction = SIMD3<Float>(0.95, 0.78, 0.95) / length(SIMD3<Float>(0.95, 0.78, 0.95))
        return Result(target: center, position: center + direction * distance,
                      near: max(0.01, distance - radius * 2.2), far: distance + radius * 4)
    }
}
