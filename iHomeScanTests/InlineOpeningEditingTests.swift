import CoreGraphics
import Foundation
import Testing
@testable import iHomeScan

@Suite("Inline opening precision editing")
struct InlineOpeningEditingTests {
    @Test("Door tap has priority in the host wall region")
    func doorHitPriority() {
        let plan = fixturePlan()
        let targets = PrecisionOpeningHitTesting.targets(for: plan, transform: .identity)
        #expect(PrecisionOpeningHitTesting.selectedOpening(at: CGPoint(x: 1.1, y: 0), targets: targets) == plan.openings[0].id)
    }

    @Test("Selected opening dimension label resolves to its stable ID")
    func labelHit() {
        let plan = fixturePlan()
        let id = plan.openings[0].id
        let targets = PrecisionOpeningHitTesting.targets(for: plan, transform: .identity, selectedOpeningID: id)
        let center = targets[0].labelBounds.map { CGPoint(x: $0.midX, y: $0.midY) }!
        #expect(PrecisionOpeningHitTesting.selectedOpening(at: center, targets: targets) == id)
    }

    @Test("Hit testing survives rotation, zoom and pan transform")
    func transformedHit() {
        let plan = fixturePlan()
        let transform = CGAffineTransform(translationX: 80, y: 120).rotated(by: .pi / 5).scaledBy(x: 2.2, y: 2.2)
        let targets = PrecisionOpeningHitTesting.targets(for: plan, transform: transform)
        let target = targets[0]
        let point = CGPoint(x: (target.start.x + target.end.x) / 2, y: (target.start.y + target.end.y) / 2)
        #expect(PrecisionOpeningHitTesting.selectedOpening(at: point, targets: targets) == plan.openings[0].id)
    }

    @Test("Start offset edit moves only the selected opening")
    func startOffsetPreview() {
        let plan = fixturePlan(twoOpenings: true)
        let originalSecondCenter = plan.openings[1].horizontalAnchor
        var draft = OpeningMeasurementDraft.make(opening: plan.openings[0], plan: plan)
        draft.referenceEndpoint = .wallStart
        draft.startOffsetMillimeters = "700"
        let preview = OpeningEditEngine.preview(draft: draft, in: plan)
        #expect(preview?.isValid == true)
        let placement = preview?.resolution.placements.first { $0.openingID == draft.openingID }
        #expect(abs((placement?.startOffset ?? 0) - 0.7) < 0.0001)
        switch (preview?.candidatePlan.openings[1].horizontalAnchor, originalSecondCenter) {
        case let (.distanceFromStart(revised)?, .distanceFromStart(original)):
            #expect(abs(revised.value - original.value) < 0.0001)
        default:
            Issue.record("Unrelated opening anchor must remain representable")
        }
        #expect(preview?.candidatePlan.vertices == plan.vertices)
    }

    @Test("Width and vertical dimensions update real geometry")
    func widthAndHeightPreview() {
        let plan = fixturePlan()
        var draft = OpeningMeasurementDraft.make(opening: plan.openings[0], plan: plan)
        draft.referenceEndpoint = .wallStart
        draft.widthMillimeters = "1000"
        draft.heightMillimeters = "2150"
        draft.lowerElevationMillimeters = "25"
        let preview = OpeningEditEngine.preview(draft: draft, in: plan)
        let opening = preview?.candidatePlan.openings[0]
        #expect(preview?.isValid == true)
        #expect(abs((opening?.width?.value ?? 0) - 1) < 0.0001)
        #expect(abs((opening?.height?.value ?? 0) - 2.15) < 0.0001)
        #expect(abs((opening?.verticalOffset?.value ?? 0) - 0.025) < 0.0001)
    }

    @Test("Overlapping opening preview is blocked")
    func overlapBlocked() {
        let plan = fixturePlan(twoOpenings: true)
        var draft = OpeningMeasurementDraft.make(opening: plan.openings[0], plan: plan)
        draft.referenceEndpoint = .wallStart
        draft.startOffsetMillimeters = "1900"
        draft.widthMillimeters = "1000"
        let preview = OpeningEditEngine.preview(draft: draft, in: plan)
        #expect(preview?.isValid == false)
        #expect(preview?.resolution.conflicts.contains { $0.code == .overlappingOpenings } == true)
    }

    @Test("Laser toggle creates user-declared verified provenance")
    func laserProvenance() {
        let plan = fixturePlan()
        var draft = OpeningMeasurementDraft.make(opening: plan.openings[0], plan: plan)
        draft.referenceEndpoint = .wallStart
        draft.laserVerified = true
        let preview = OpeningEditEngine.preview(draft: draft, in: plan)
        let width = preview?.candidatePlan.openings[0].architecturalMetadata?.measurements.first {
            $0.kind == .width && $0.value.provenance.source != .derived
        }
        #expect(width?.value.provenance.source == .laserVerified)
        #expect(width?.value.provenance.verificationStatus == .verified)
    }

    @Test("Invalid input never mutates committed plan")
    func invalidInputPreservesPlan() {
        let plan = fixturePlan()
        let committed = plan
        var draft = OpeningMeasurementDraft.make(opening: plan.openings[0], plan: plan)
        draft.referenceEndpoint = .wallStart
        draft.widthMillimeters = "-5"
        #expect(OpeningEditEngine.preview(draft: draft, in: plan) == nil)
        #expect(plan == committed)
    }

    private func fixturePlan(twoOpenings: Bool = false) -> ParametricFloorPlan {
        let source = GeometrySourceMetadata(sourceElementID: UUID(uuidString: "B0000000-0000-0000-0000-000000000001"), confidence: .high, originalStart: nil, originalEnd: nil, transform: nil)
        let startID = UUID(uuidString: "B1000000-0000-0000-0000-000000000001")!
        let endID = UUID(uuidString: "B1000000-0000-0000-0000-000000000002")!
        let wallID = UUID(uuidString: "B2000000-0000-0000-0000-000000000001")!
        let doorID = UUID(uuidString: "B3000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "B3000000-0000-0000-0000-000000000002")!
        let provenance = MeasurementProvenance(source: .lidarEstimated, verificationStatus: .estimated, timestamp: nil, uncertainty: nil)
        func opening(_ id: UUID, start: Double, width: Double, kind: WallOpeningKind) -> WallOpening {
            let measurements = [
                OpeningMeasurement(id: UUID(), openingID: id, kind: .offsetFromStart,
                                   value: .init(value: start, provenance: provenance),
                                   reference: .init(endpoint: .wallStart, vertexID: startID, reliability: .estimated), relatedConstraintIDs: []),
                OpeningMeasurement(id: UUID(), openingID: id, kind: .width,
                                   value: .init(value: width, provenance: provenance), reference: nil, relatedConstraintIDs: [])
            ]
            return WallOpening(id: id, hostWallID: wallID, kind: kind,
                               width: .init(value: width, provenance: provenance), height: .init(value: 2.1, provenance: provenance),
                               verticalOffset: .init(value: 0, provenance: provenance),
                               horizontalAnchor: .distanceFromStart(.init(value: start + width / 2, provenance: provenance)),
                               source: source,
                               architecturalMetadata: .init(measurements: measurements, completeness: .partial, doorSwing: nil))
        }
        var openings = [opening(doorID, start: 0.65, width: 0.9, kind: .door)]
        if twoOpenings { openings.append(opening(secondID, start: 2.5, width: 0.8, kind: .window)) }
        return ParametricFloorPlan(
            id: UUID(uuidString: "B4000000-0000-0000-0000-000000000001")!, projectID: UUID(), roomID: UUID(), sourceScanID: UUID(),
            coordinateSystem: "test", completeness: .partial,
            vertices: [.init(id: startID, position: .init(x: 0, y: 0), source: source, mergedEndpointKeys: []),
                       .init(id: endID, position: .init(x: 4.25, y: 0), source: source, mergedEndpointKeys: [])],
            walls: [.init(id: wallID, startVertexID: startID, endVertexID: endID, height: .init(value: 2.8, provenance: provenance), thickness: nil, source: source)],
            openings: openings, columns: [], beams: [], floorBoundary: nil, endpointMerges: [],
            revision: .init(number: 1, createdAt: .init(timeIntervalSince1970: 0), source: .lidarEstimated)
        )
    }
}
