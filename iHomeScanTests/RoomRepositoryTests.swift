import Foundation
import Testing
import SwiftData
@testable import iHomeScan

@MainActor
@Suite("Floors and rooms")
struct RoomRepositoryTests {
    private func makeProject(_ env: TestEnvironment) throws -> (Project, Floor) {
        let project = try env.projects.create(name: "Project")
        return (project, try #require(project.floors.first))
    }

    @Test("Rooms belong to a floor and project; unmeasured rooms have no area")
    func addRoomRelationships() throws {
        let env = try TestEnvironment()
        let (project, floor) = try makeProject(env)

        let room = try env.rooms.addRoom(to: floor, draft: RoomDraft(name: " Bedroom ", type: .bedroom))

        #expect(room.name == "Bedroom")
        #expect(room.floor?.id == floor.id)
        #expect(room.floor?.project?.id == project.id)
        #expect(project.allRooms.map(\.id) == [room.id])
        #expect(!room.isMeasured)
        #expect(room.effectiveArea == nil)
        #expect(project.totalArea == nil)
    }

    @Test("Updating a room changes fields, type and measurements")
    func updateRoom() throws {
        let env = try TestEnvironment()
        let (_, floor) = try makeProject(env)
        let room = try env.rooms.addRoom(to: floor, draft: RoomDraft(name: "Room"))

        try env.rooms.updateRoom(room, with: RoomDraft(name: "Kitchen", type: .kitchen, width: 3.0, length: 2.8, height: 2.7))
        #expect(room.name == "Kitchen")
        #expect(room.type == .kitchen)
        #expect(room.effectiveArea == 3.0 * 2.8) // derived from width × length

        try env.rooms.updateRoom(room, with: RoomDraft(name: "Kitchen", type: nil, area: 9.5))
        #expect(room.type == nil)
        #expect(room.width == nil)
        #expect(room.effectiveArea == 9.5) // explicit area wins
    }

    @Test("Invalid measurements are rejected and nothing is changed", arguments: [0.0, -1.0, Double.nan, .infinity])
    func invalidMeasurements(value: Double) throws {
        let env = try TestEnvironment()
        let (_, floor) = try makeProject(env)
        let room = try env.rooms.addRoom(to: floor, draft: RoomDraft(name: "Room", width: 2))

        #expect(throws: RepositoryError.invalidMeasurement) {
            try env.rooms.updateRoom(room, with: RoomDraft(name: "Room", width: value))
        }
        #expect(room.width == 2)
    }

    @Test("Deleting a room removes its assets and files only")
    func deleteRoom() throws {
        let env = try TestEnvironment()
        let (project, floor) = try makeProject(env)
        let room = try env.rooms.addRoom(to: floor, draft: RoomDraft(name: "A"))
        let other = try env.rooms.addRoom(to: floor, draft: RoomDraft(name: "B"))
        let photo = try env.assets.addAsset(Data("x".utf8), type: .inspectionPhoto, fileName: "x.jpg", project: project, room: room)
        let path = photo.relativeFilePath

        try env.rooms.deleteRoom(room)

        #expect(project.allRooms.map(\.id) == [other.id])
        #expect(try env.count(LocalAsset.self) == 0)
        #expect(!env.files.fileExists(atRelativePath: path))
    }

    @Test("Floors get increasing levels and can be renamed")
    func floors() throws {
        let env = try TestEnvironment()
        let (project, _) = try makeProject(env)

        let second = try env.rooms.addFloor(to: project)
        #expect(second.level == 2)
        #expect(project.sortedFloors.map(env.settings.floorName) == ["Floor 1", "Floor 2"])

        try env.rooms.renameFloor(second, to: "Attic")
        #expect(second.name == "Attic")
        #expect(throws: RepositoryError.emptyName) { try env.rooms.renameFloor(second, to: " ") }
    }

    @Test("Deleting a floor cascades to its rooms; the last floor cannot be deleted")
    func deleteFloor() throws {
        let env = try TestEnvironment()
        let (project, first) = try makeProject(env)
        let second = try env.rooms.addFloor(to: project, name: "Floor 2")
        try env.rooms.addRoom(to: second, draft: RoomDraft(name: "Upstairs"))
        try env.rooms.addRoom(to: first, draft: RoomDraft(name: "Downstairs"))
        let plan = try env.assets.savePlan(SampleProjectSeeder.plan, for: second)

        try env.rooms.deleteFloor(second)

        #expect(project.floors.map(\.id) == [first.id])
        #expect(project.allRooms.map(\.name) == ["Downstairs"])
        #expect(!env.files.fileExists(atRelativePath: plan.relativeFilePath))
        #expect(throws: RepositoryError.lastFloor) { try env.rooms.deleteFloor(first) }
    }

    @Test("Length input is parsed in the selected unit and stored in meters")
    func parseLength() throws {
        let env = try TestEnvironment(language: .russian)
        env.settings.units = .millimeters
        #expect(try env.settings.parseLength("4 200").get() == 4.2)
        env.settings.units = .meters
        #expect(try env.settings.parseLength("4,25").get() == 4.25)
        #expect(try env.settings.parseLength("").get() == nil)
        #expect(throws: RepositoryError.invalidMeasurement) { try env.settings.parseLength("abc").get() }
        #expect(throws: RepositoryError.invalidMeasurement) { try env.settings.parseLength("-3").get() }
    }
}
