import CoreGraphics
import Foundation
import Testing
@testable import iHomeScan

@Suite("Floor plan presentation")
struct FloorPlanPresentationTests {
    private func plan(walls: [[CGPoint]], dimensions: [FloorPlan.Dimension] = []) -> FloorPlan {
        let points = walls.flatMap { $0 }
        let bounds = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        return FloorPlan(bounds: bounds, rooms: [], outerWalls: walls, innerWalls: [],
                         doors: [], windows: [], dimensions: dimensions)
    }

    private func rotated(_ point: CGPoint, by angle: CGFloat) -> CGPoint {
        point.applying(CGAffineTransform(rotationAngle: angle))
    }

    @Test("Dominant architectural axis is aligned without changing coordinates")
    func dominantAlignmentAndCoordinatePreservation() throws {
        let angle = CGFloat.pi / 6
        let originalWalls = [
            [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0)].map { rotated($0, by: angle) },
            [CGPoint(x: 5, y: 0), CGPoint(x: 5, y: 3)].map { rotated($0, by: angle) },
            [CGPoint(x: 5, y: 3), CGPoint(x: 0, y: 3)].map { rotated($0, by: angle) },
        ]
        let subject = plan(walls: originalWalls)
        let encodedBefore = try subject.encoded()
        let result = FloorPlanAlignmentEngine.alignment(for: subject)

        #expect(abs(result.rotation + angle) < 0.001)
        #expect(result.confidence > 0.99)
        #expect(try subject.encoded() == encodedBefore)
    }

    @Test("Irregular directions with no dominant axis are not arbitrarily rotated")
    func irregularAlignment() {
        let subject = plan(walls: [
            [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 0)],
            [CGPoint(x: 0, y: 0), CGPoint(x: 1.41, y: 1.41)],
            [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 2)],
            [CGPoint(x: 0, y: 0), CGPoint(x: -1.41, y: 1.41)],
        ])
        let result = FloorPlanAlignmentEngine.alignment(for: subject)
        #expect(result.rotation == 0)
        #expect(result.confidence < 0.55)
    }

    @Test("Dimension layout prevents collisions and remains inside the canvas")
    func dimensionCollisionAndBounds() {
        let dimensions = (0..<8).map { index in
            FloorPlan.Dimension(
                start: CGPoint(x: 0, y: CGFloat(index) * 0.04),
                end: CGPoint(x: 4 - CGFloat(index) * 0.08, y: CGFloat(index) * 0.04),
                value: 4 - Double(index) * 0.08,
                labelPosition: .zero, labelRotation: index.isMultiple(of: 2) ? 175 : -95
            )
        }
        let annotations = FloorPlanDimensionLayoutEngine.layout(
            dimensions: dimensions,
            transform: CGAffineTransform(translationX: 40, y: 100).scaledBy(x: 70, y: 70),
            canvasBounds: CGRect(x: 0, y: 0, width: 390, height: 300),
            planCenter: CGPoint(x: 2, y: 1),
            textForValue: { String(format: "%.2f m", $0) }
        )

        #expect(!annotations.isEmpty)
        for (index, annotation) in annotations.enumerated() {
            #expect(annotation.textRotation == 0)
            #expect(CGRect(x: 8, y: 8, width: 374, height: 284).contains(annotation.labelBounds))
            for other in annotations.dropFirst(index + 1) {
                #expect(!annotation.labelBounds.intersects(other.labelBounds))
            }
        }
    }

    @Test("Short and invalid dimensions are filtered while partial geometry remains usable")
    func shortSegmentFiltering() {
        let dimensions = [
            FloorPlan.Dimension(start: .zero, end: CGPoint(x: 0.2, y: 0), value: 0.2,
                                labelPosition: .zero, labelRotation: 0),
            FloorPlan.Dimension(start: .zero, end: CGPoint(x: 2, y: 0), value: 2,
                                labelPosition: .zero, labelRotation: 0),
            FloorPlan.Dimension(start: .zero, end: CGPoint(x: CGFloat.infinity, y: 0),
                                value: Double.infinity,
                                labelPosition: .zero, labelRotation: 0),
        ]
        let annotations = FloorPlanDimensionLayoutEngine.layout(
            dimensions: dimensions,
            transform: CGAffineTransform(translationX: 40, y: 100).scaledBy(x: 100, y: 100),
            canvasBounds: CGRect(x: 0, y: 0, width: 320, height: 240),
            planCenter: CGPoint(x: 1, y: 1),
            textForValue: { "\($0) m" }
        )
        #expect(annotations.map { $0.sourceIndex } == [1])
    }

    @Test("Rotated fit transform preserves zoom and pan behavior")
    func rotatedZoomAndPan() {
        let subject = plan(walls: [[CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 2)]])
        let angle = -CGFloat.pi / 8
        let fitted = FloorPlanCanvas.transform(for: subject, in: CGSize(width: 390, height: 700),
                                               zoom: 1, offset: .zero, rotation: angle)
        let zoomed = FloorPlanCanvas.transform(for: subject, in: CGSize(width: 390, height: 700),
                                               zoom: 2, offset: CGSize(width: 20, height: -15),
                                               rotation: angle)
        let vector = CGPoint(x: 5, y: 2)
        let fittedLength = hypot(vector.applying(fitted).x - CGPoint.zero.applying(fitted).x,
                                 vector.applying(fitted).y - CGPoint.zero.applying(fitted).y)
        let zoomedLength = hypot(vector.applying(zoomed).x - CGPoint.zero.applying(zoomed).x,
                                 vector.applying(zoomed).y - CGPoint.zero.applying(zoomed).y)
        #expect(abs(zoomedLength / fittedLength - 2) < 0.001)
    }

    @Test("Camera framing is finite, practical and rejects invalid bounds")
    func cameraFraming() {
        let result = ArchitecturalCameraFraming.frame(
            center: SIMD3<Float>(1, 1.5, -2), extents: SIMD3<Float>(6, 3, 5)
        )
        #expect(result != nil)
        #expect(result?.position != result?.target)
        #expect((result?.near ?? 0) > 0)
        #expect((result?.far ?? 0) > (result?.near ?? 0))
        #expect(ArchitecturalCameraFraming.frame(center: .zero, extents: .zero) == nil)
        #expect(ArchitecturalCameraFraming.frame(
            center: SIMD3<Float>(.infinity, 0, 0), extents: .one
        ) == nil)
    }
}
