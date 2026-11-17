import Foundation

/// One explicit policy for user-facing edited floor area.
/// Historic scan values remain stored separately; a valid closed precision boundary wins.
enum PrecisionAreaPolicy {
    static func authoritativeArea(
        precisionPlan: ParametricFloorPlan?,
        storedArea: Double?
    ) -> Double? {
        precisionPlan?.derivedFloorArea ?? storedArea
    }

    static func projectTotal(
        rooms: [Room],
        replacingRoomID: UUID? = nil,
        with area: Double? = nil
    ) -> Double? {
        let values = rooms.compactMap { room -> Double? in
            if room.id == replacingRoomID { return area }
            return room.effectiveArea
        }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}
