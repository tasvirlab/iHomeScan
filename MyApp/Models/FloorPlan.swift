import Foundation
import CoreGraphics

/// 2D floor plan geometry for one floor, stored on disk as JSON (asset type `.roomGeometry`).
///
/// All coordinates and lengths are in **meters** (the canonical unit), origin at the
/// top-left outer wall corner, y axis pointing down. Stage 2 will produce this from RoomPlan.
struct FloorPlan: Codable, Hashable {
    /// Bumped when the JSON layout changes so older files can still be decoded.
    static let currentFormatVersion = 1

    /// A room outline. `id` is matched against `Room.geometryIdentifier` in the database.
    struct PlanRoom: Codable, Hashable, Identifiable {
        let id: String
        let rect: CGRect
        /// Where the room's label is centered on the plan.
        let labelCenter: CGPoint
    }

    struct Segment: Codable, Hashable {
        let start: CGPoint
        let end: CGPoint
    }

    /// A door drawn as a leaf line plus a swing arc around `hinge`.
    struct Door: Codable, Hashable {
        let hinge: CGPoint
        let radius: CGFloat
        /// Degrees; 0° = right, 90° = down.
        let startAngle: Double
        let endAngle: Double
    }

    /// A dimension line along an outer side of the plan.
    struct Dimension: Codable, Hashable {
        let start: CGPoint
        let end: CGPoint
        /// Measured length in meters.
        let value: Double
        let labelPosition: CGPoint
        /// Label rotation in degrees.
        let labelRotation: Double
    }

    var formatVersion: Int = FloorPlan.currentFormatVersion
    let bounds: CGRect
    let rooms: [PlanRoom]
    /// Outer wall polylines (gaps mark the entrance).
    let outerWalls: [[CGPoint]]
    let innerWalls: [Segment]
    let doors: [Door]
    let windows: [CGRect]
    let dimensions: [Dimension]

    /// Returns a copy with every coordinate multiplied by `factor` (e.g. 1000 for millimeters).
    func scaled(by factor: CGFloat) -> FloorPlan {
        func p(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * factor, y: point.y * factor) }
        func r(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX * factor, y: rect.minY * factor, width: rect.width * factor, height: rect.height * factor)
        }
        return FloorPlan(
            formatVersion: formatVersion,
            bounds: r(bounds),
            rooms: rooms.map { PlanRoom(id: $0.id, rect: r($0.rect), labelCenter: p($0.labelCenter)) },
            outerWalls: outerWalls.map { $0.map(p) },
            innerWalls: innerWalls.map { Segment(start: p($0.start), end: p($0.end)) },
            doors: doors.map { Door(hinge: p($0.hinge), radius: $0.radius * factor,
                                    startAngle: $0.startAngle, endAngle: $0.endAngle) },
            windows: windows.map(r),
            dimensions: dimensions.map {
                Dimension(start: p($0.start), end: p($0.end), value: $0.value,
                          labelPosition: p($0.labelPosition), labelRotation: $0.labelRotation)
            }
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> FloorPlan {
        try JSONDecoder().decode(FloorPlan.self, from: data)
    }
}

/// Text shown for a room on the plan, sourced from the database `Room`.
struct PlanRoomLabel: Hashable {
    let name: String
    let area: Double?
}
