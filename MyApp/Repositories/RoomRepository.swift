import Foundation
import SwiftData

/// Editable room fields. Measurements are optional and in meters / square meters.
struct RoomDraft: Equatable {
    var name: String
    var type: RoomType?
    var width: Double?
    var length: Double?
    var height: Double?
    var area: Double?

    init(name: String = "", type: RoomType? = nil, width: Double? = nil,
         length: Double? = nil, height: Double? = nil, area: Double? = nil) {
        self.name = name
        self.type = type
        self.width = width
        self.length = length
        self.height = height
        self.area = area
    }

    init(_ room: Room) {
        self.init(name: room.name, type: room.type, width: room.width,
                  length: room.length, height: room.height, area: room.area)
    }
}

/// Manages floors and rooms within a project.
struct RoomRepository {
    let context: ModelContext
    let files: LocalFileStorageService

    // MARK: - Floors

    /// Adds the next floor. An empty name means "use the localized default name".
    @discardableResult
    func addFloor(to project: Project, name: String = "") throws -> Floor {
        let level = (project.floors.map(\.level).max() ?? 0) + 1
        let floor = Floor(level: level, name: name.nilIfBlank ?? "")
        context.insert(floor)
        floor.project = project
        project.updatedAt = .now
        try context.save()
        return floor
    }

    func renameFloor(_ floor: Floor, to name: String) throws {
        guard let name = name.nilIfBlank else { throw RepositoryError.emptyName }
        floor.name = name
        floor.project?.updatedAt = .now
        try context.save()
    }

    /// Deletes a floor with its rooms and files. A project always keeps at least one floor.
    func deleteFloor(_ floor: Floor) throws {
        guard let project = floor.project, project.floors.count > 1 else { throw RepositoryError.lastFloor }
        let paths = floor.assets.map(\.relativeFilePath) + floor.rooms.flatMap { $0.assets.map(\.relativeFilePath) }
        project.updatedAt = .now
        context.delete(floor)
        try context.save()
        removeFiles(paths)
    }

    // MARK: - Rooms

    @discardableResult
    func addRoom(to floor: Floor, draft: RoomDraft) throws -> Room {
        let room = Room(name: "")
        try apply(draft, to: room)
        context.insert(room)
        room.floor = floor
        floor.project?.updatedAt = .now
        try context.save()
        return room
    }

    func updateRoom(_ room: Room, with draft: RoomDraft) throws {
        try apply(draft, to: room)
        room.updatedAt = .now
        room.floor?.project?.updatedAt = .now
        try context.save()
    }

    func deleteRoom(_ room: Room) throws {
        let paths = room.assets.map(\.relativeFilePath)
        room.floor?.project?.updatedAt = .now
        context.delete(room)
        try context.save()
        removeFiles(paths)
    }

    // MARK: - Helpers

    private func apply(_ draft: RoomDraft, to room: Room) throws {
        guard let name = draft.name.nilIfBlank else { throw RepositoryError.emptyName }
        for value in [draft.width, draft.length, draft.height, draft.area].compactMap({ $0 }) {
            guard value.isFinite, value > 0 else { throw RepositoryError.invalidMeasurement }
        }
        room.name = name
        room.type = draft.type
        room.width = draft.width
        room.length = draft.length
        room.height = draft.height
        room.area = draft.area
    }

    /// Best effort: a leftover file is harmless and is not referenced by any metadata.
    private func removeFiles(_ paths: [String]) {
        for path in paths { try? files.deleteFile(atRelativePath: path) }
    }
}
