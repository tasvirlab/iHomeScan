#if DEBUG
import SwiftUI

/// Deterministic UI-test-only floor plan. It is never presented without the explicit launch argument.
struct PrecisionTapUITestFixtureView: View {
    private static let persistedMetersKey = "precision.uiTest.persistedMeters"
    private static let wallID = UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
    @State private var selectedRoomID: String?
    @State private var selectedWallID: UUID?
    @State private var input = ""
    @State private var laserVerified = false
    @State private var anchor: WallLengthAnchorStrategy?
    @State private var plan: ParametricFloorPlan

    init() {
        if ProcessInfo.processInfo.arguments.contains("--reset-precision-ui-test") {
            UserDefaults.standard.removeObject(forKey: Self.persistedMetersKey)
        }
        _plan = State(initialValue: Self.fixtureParametricPlan())
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("DEBUG TEST FIXTURE")
                .font(.caption2.monospaced())
                .foregroundStyle(Palette.inkTertiary)
                .accessibilityIdentifier("precision.fixture.label")
            FloorPlanViewer(
                plan: Self.fixtureFloorPlan,
                labels: ["fixture-room": .init(name: "Fixture room", area: 12)],
                selectedRoomID: $selectedRoomID,
                precisionPlan: plan,
                selectedPrecisionWallID: $selectedWallID,
                onPrecisionWallSelected: selectWall
            )
        }
        .background(Palette.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selectedWallID != nil {
                InlinePrecisionMeasurementSheet(
                    currentMillimeters: PrecisionMeasurementInput.millimeters(fromMeters: plan.walls.first?.length(in: plan)),
                    currentLabelKey: "precision.inline.current",
                    input: $input,
                    laserVerified: $laserVerified,
                    anchor: $anchor,
                    requiresAnchorChoice: false,
                    hasValidPreview: PrecisionMeasurementInput.meters(fromMillimeters: input) != nil,
                    hasConflict: false,
                    isSaving: false,
                    onConfirm: confirm,
                    onClose: { selectedWallID = nil }
                )
            }
        }
    }

    private func selectWall(_ id: UUID) {
        selectedWallID = id
        input = PrecisionMeasurementInput.millimeters(fromMeters: plan.wall(id: id)?.length(in: plan))
    }

    private func confirm() {
        guard let meters = PrecisionMeasurementInput.meters(fromMillimeters: input),
              let wall = plan.walls.first,
              let startIndex = plan.vertices.firstIndex(where: { $0.id == wall.startVertexID }),
              let endIndex = plan.vertices.firstIndex(where: { $0.id == wall.endVertexID }) else { return }
        let start = plan.vertices[startIndex].position
        let end = plan.vertices[endIndex].position
        let length = max(start.distance(to: end), 0.001)
        plan.vertices[endIndex].position = .init(
            x: start.x + (end.x - start.x) / length * meters,
            y: start.y + (end.y - start.y) / length * meters
        )
        UserDefaults.standard.set(meters, forKey: Self.persistedMetersKey)
        selectedWallID = nil
    }

    private static let fixtureFloorPlan = FloorPlan(
        bounds: CGRect(x: 0, y: 0, width: 4, height: 3),
        rooms: [.init(id: "fixture-room", rect: CGRect(x: 0, y: 0, width: 4, height: 3), labelCenter: CGPoint(x: 2, y: 1.5))],
        outerWalls: [[CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 3), CGPoint(x: 0, y: 3), CGPoint(x: 0, y: 0)]],
        innerWalls: [], doors: [], windows: [],
        dimensions: [.init(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 4, y: 0), value: 4,
                           labelPosition: CGPoint(x: 2, y: -0.4), labelRotation: 0)]
    )

    private static func fixtureParametricPlan() -> ParametricFloorPlan {
        let source = GeometrySourceMetadata(sourceElementID: nil, confidence: .high, originalStart: nil, originalEnd: nil, transform: nil)
        let startID = UUID(uuidString: "A2000000-0000-0000-0000-000000000001")!
        let endID = UUID(uuidString: "A2000000-0000-0000-0000-000000000002")!
        let persisted = UserDefaults.standard.double(forKey: persistedMetersKey)
        let length = persisted > 0 ? persisted : 4
        return ParametricFloorPlan(
            id: UUID(uuidString: "A3000000-0000-0000-0000-000000000001")!,
            projectID: UUID(), roomID: UUID(), sourceScanID: UUID(),
            coordinateSystem: "DEBUG fixture; meters", completeness: .partial,
            vertices: [
                .init(id: startID, position: .init(x: 0, y: 0), source: source, mergedEndpointKeys: []),
                .init(id: endID, position: .init(x: length, y: 0), source: source, mergedEndpointKeys: [])
            ],
            walls: [.init(id: wallID, startVertexID: startID, endVertexID: endID, height: nil, thickness: nil, source: source)],
            openings: [], columns: [], beams: [], floorBoundary: nil, endpointMerges: [],
            revision: .init(number: 1, createdAt: .init(timeIntervalSince1970: 0), source: .manualEntered)
        )
    }
}
#endif
