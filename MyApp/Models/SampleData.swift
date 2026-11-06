import Foundation
import CoreGraphics
import SwiftData

/// SAMPLE DATA — one demo project ("Chilonzor") with an illustrative floor plan, inserted on
/// first launch so the app isn't empty. It is flagged `isSample` and shown with a "Sample data"
/// badge everywhere; its measurements are NOT from a real scan. Once deleted it never returns.
enum SampleProjectSeeder {
    static let seededKey = "seed.sampleProject.v1"

    /// Inserts the demo project once per install. Returns the project if it was created.
    @discardableResult
    static func seedIfNeeded(
        context: ModelContext,
        files: LocalFileStorageService,
        settings: AppSettings,
        defaults: UserDefaults = .standard
    ) throws -> Project? {
        guard !defaults.bool(forKey: seededKey) else { return nil }

        let project = Project(name: settings.t("sample.project.chilonzor"), status: .scanned, isSample: true)
        context.insert(project)
        let floor = Floor(level: 1, name: "")
        context.insert(floor)
        floor.project = project

        for room in rooms {
            let model = Room(
                name: settings.t(room.nameKey),
                type: room.type,
                width: Double(room.rect.width),
                length: Double(room.rect.height),
                height: 2.7,
                geometryIdentifier: room.id
            )
            context.insert(model)
            model.floor = floor
        }
        try context.save()

        try AssetRepository(context: context, files: files).savePlan(plan, for: floor)
        defaults.set(true, forKey: seededKey)
        return project
    }

    private struct SampleRoom {
        let id: String
        let nameKey: String
        let type: RoomType
        let rect: CGRect
        let labelCenter: CGPoint
    }

    /// 7.8 × 7.6 m two-room flat, five rooms totalling 59.28 m².
    private static let rooms: [SampleRoom] = [
        SampleRoom(id: "living", nameKey: "room.living", type: .living,
                   rect: CGRect(x: 0, y: 0, width: 4.2, height: 4.8), labelCenter: CGPoint(x: 2.1, y: 2.4)),
        SampleRoom(id: "bedroom", nameKey: "room.bedroom", type: .bedroom,
                   rect: CGRect(x: 4.2, y: 0, width: 3.6, height: 4.8), labelCenter: CGPoint(x: 6.0, y: 2.4)),
        SampleRoom(id: "kitchen", nameKey: "room.kitchen", type: .kitchen,
                   rect: CGRect(x: 0, y: 4.8, width: 3.0, height: 2.8), labelCenter: CGPoint(x: 1.4, y: 6.2)),
        SampleRoom(id: "hallway", nameKey: "room.hallway", type: .hallway,
                   rect: CGRect(x: 3.0, y: 4.8, width: 2.8, height: 2.8), labelCenter: CGPoint(x: 4.4, y: 6.1)),
        SampleRoom(id: "bathroom", nameKey: "room.bathroom", type: .bathroom,
                   rect: CGRect(x: 5.8, y: 4.8, width: 2.0, height: 2.8), labelCenter: CGPoint(x: 6.8, y: 5.8)),
    ]

    static let plan = FloorPlan(
        bounds: CGRect(x: 0, y: 0, width: 7.8, height: 7.6),
        rooms: rooms.map { FloorPlan.PlanRoom(id: $0.id, rect: $0.rect, labelCenter: $0.labelCenter) },
        outerWalls: [
            [CGPoint(x: 4.0, y: 7.6), CGPoint(x: 0, y: 7.6), CGPoint(x: 0, y: 0),
             CGPoint(x: 7.8, y: 0), CGPoint(x: 7.8, y: 7.6), CGPoint(x: 4.9, y: 7.6)],
        ],
        innerWalls: [
            segment(4.2, 0, 4.2, 4.8),
            segment(0, 4.8, 3.3, 4.8),
            segment(4.1, 4.8, 4.5, 4.8),
            segment(5.3, 4.8, 7.8, 4.8),
            segment(3.0, 4.8, 3.0, 5.2),
            segment(3.0, 5.9, 3.0, 7.6),
            segment(5.8, 4.8, 5.8, 6.6),
            segment(5.8, 7.3, 5.8, 7.6),
        ],
        doors: [
            FloorPlan.Door(hinge: CGPoint(x: 3.3, y: 4.8), radius: 0.8, startAngle: -90, endAngle: 0),
            FloorPlan.Door(hinge: CGPoint(x: 5.3, y: 4.8), radius: 0.8, startAngle: -90, endAngle: -180),
            FloorPlan.Door(hinge: CGPoint(x: 3.0, y: 5.2), radius: 0.7, startAngle: 180, endAngle: 90),
            FloorPlan.Door(hinge: CGPoint(x: 5.8, y: 7.3), radius: 0.7, startAngle: 0, endAngle: -90),
            FloorPlan.Door(hinge: CGPoint(x: 4.0, y: 7.6), radius: 0.9, startAngle: -90, endAngle: 0),
        ],
        windows: [
            CGRect(x: 1.2, y: -0.11, width: 1.8, height: 0.22),
            CGRect(x: 5.1, y: -0.11, width: 1.8, height: 0.22),
            CGRect(x: -0.11, y: 5.5, width: 0.22, height: 1.4),
            CGRect(x: 7.69, y: 1.5, width: 0.22, height: 1.7),
        ],
        dimensions: [
            dimension(0, -0.7, 4.2, -0.7, value: 4.2, label: (2.1, -0.8), rotation: 0),
            dimension(4.2, -0.7, 7.8, -0.7, value: 3.6, label: (6.0, -0.8), rotation: 0),
            dimension(-0.7, 0, -0.7, 4.8, value: 4.8, label: (-0.8, 2.4), rotation: -90),
            dimension(-0.7, 4.8, -0.7, 7.6, value: 2.8, label: (-0.8, 6.2), rotation: -90),
            dimension(0, 8.3, 3.0, 8.3, value: 3.0, label: (1.5, 8.59), rotation: 0),
            dimension(3.0, 8.3, 5.8, 8.3, value: 2.8, label: (4.4, 8.59), rotation: 0),
            dimension(5.8, 8.3, 7.8, 8.3, value: 2.0, label: (6.8, 8.59), rotation: 0),
            dimension(8.5, 0, 8.5, 7.6, value: 7.6, label: (8.6, 3.8), rotation: 90),
        ]
    )

    private static func segment(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> FloorPlan.Segment {
        FloorPlan.Segment(start: CGPoint(x: x1, y: y1), end: CGPoint(x: x2, y: y2))
    }

    private static func dimension(
        _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat,
        value: Double, label: (CGFloat, CGFloat), rotation: Double
    ) -> FloorPlan.Dimension {
        FloorPlan.Dimension(
            start: CGPoint(x: x1, y: y1), end: CGPoint(x: x2, y: y2), value: value,
            labelPosition: CGPoint(x: label.0, y: label.1), labelRotation: rotation
        )
    }
}
