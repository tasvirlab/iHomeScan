import Foundation
import Testing
import SwiftData
@testable import iHomeScan

@MainActor
@Suite("Projects")
struct ProjectRepositoryTests {
    @Test("Created project gets a default floor and local-only sync state")
    func createProject() throws {
        let env = try TestEnvironment()
        let project = try env.projects.create(name: "  Chilonzor 9  ", description: " ")
        let floor = try #require(project.floors.first)

        #expect(project.name == "Chilonzor 9")
        #expect(project.projectDescription == nil)
        #expect(project.status == .draft)
        #expect(project.syncState == .localOnly)
        #expect(project.floors.count == 1)
        #expect(project.floors.first?.level == 1)
        #expect(floor.name.isEmpty) // displayed with the localized default name
        #expect(env.settings.floorName(floor) == "Floor 1")
        env.settings.language = .uzbek
        #expect(env.settings.floorName(floor) == "1-qavat")
        env.settings.language = .russian
        #expect(env.settings.floorName(floor) == "Этаж 1")
        #expect(try env.projects.fetchAll().map(\.id) == [project.id])
    }

    @Test("Empty names are rejected")
    func emptyNameRejected() throws {
        let env = try TestEnvironment()
        #expect(throws: RepositoryError.emptyName) {
            try env.projects.create(name: "   ")
        }
        #expect(try env.count(Project.self) == 0)
    }

    @Test("Projects persist across an app restart")
    func persistsAcrossRestart() throws {
        let env = try TestEnvironment(onDisk: true)
        let project = try env.projects.create(name: "Yunusobod")
        let floor = try #require(project.floors.first)
        try env.rooms.addRoom(to: floor, draft: RoomDraft(name: "Kitchen", type: .kitchen, width: 3, length: 2.8))
        let id = project.id

        try env.reopen()

        let reloaded = try #require(try env.projects.project(id: id))
        #expect(reloaded.name == "Yunusobod")
        #expect(reloaded.floors.count == 1)
        #expect(reloaded.allRooms.map(\.name) == ["Kitchen"])
        #expect(reloaded.allRooms.first?.type == .kitchen)
        #expect(abs((reloaded.totalArea ?? 0) - 8.4) < 0.0001)
    }

    @Test("Rename updates the name and modification date")
    func renameProject() async throws {
        let env = try TestEnvironment()
        let project = try env.projects.create(name: "Old")
        let before = project.updatedAt
        try await Task.sleep(for: .milliseconds(5))

        try env.projects.rename(project, to: "New name")

        #expect(project.name == "New name")
        #expect(project.updatedAt > before)
        #expect(throws: RepositoryError.emptyName) { try env.projects.rename(project, to: "") }
        #expect(project.name == "New name")
    }

    @Test("Deleting a project cascades to floors, rooms, assets and files")
    func deleteProjectCascades() throws {
        let env = try TestEnvironment()
        let project = try env.projects.create(name: "To delete")
        let floor = try #require(project.floors.first)
        let room = try env.rooms.addRoom(to: floor, draft: RoomDraft(name: "Room"))
        try env.assets.addAsset(Data("photo".utf8), type: .inspectionPhoto, fileName: "p.jpg", project: project, room: room)
        try env.assets.addAsset(Data("%PDF".utf8), type: .pdfReport, fileName: "r.pdf", project: project)
        let keeper = try env.projects.create(name: "Keep")
        let directory = env.files.projectDirectory(for: project.id)
        #expect(FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))

        try env.projects.delete(project)

        #expect(try env.count(Project.self) == 1)
        #expect(try env.count(Floor.self) == 1) // keeper's floor only
        #expect(try env.count(Room.self) == 0)
        #expect(try env.count(LocalAsset.self) == 0)
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
        #expect(try env.projects.fetchAll().map(\.id) == [keeper.id])
    }

    @Test("Orphaned project folders are cleaned up, known ones are kept")
    func orphanCleanup() throws {
        let env = try TestEnvironment()
        let project = try env.projects.create(name: "Known")
        try env.files.save(Data("a".utf8), projectID: project.id, type: .inspectionPhoto, preferredFileName: "a.jpg")
        let orphanID = UUID()
        try env.files.save(Data("b".utf8), projectID: orphanID, type: .pdfReport, preferredFileName: "b.pdf")

        let removed = try env.projects.removeOrphanedFiles()

        #expect(removed == 1)
        #expect(env.files.storedProjectIDs() == [project.id])
    }

    @Test("Sample project is seeded once and never returns after deletion")
    func sampleSeededOnce() throws {
        let env = try TestEnvironment(language: .uzbek)
        let sample = try #require(try SampleProjectSeeder.seedIfNeeded(
            context: env.context, files: env.files, settings: env.settings, defaults: env.defaults))

        #expect(sample.isSample)
        #expect(sample.name == "Chilonzor 9-kv, 2 xonali")
        #expect(sample.allRooms.count == 5)
        #expect(abs((sample.totalArea ?? 0) - 59.28) < 0.001)
        #expect(sample.floors.first?.planAsset != nil)

        try env.projects.delete(sample)
        let again = try SampleProjectSeeder.seedIfNeeded(
            context: env.context, files: env.files, settings: env.settings, defaults: env.defaults)
        #expect(again == nil)
        #expect(try env.count(Project.self) == 0)
    }
}
