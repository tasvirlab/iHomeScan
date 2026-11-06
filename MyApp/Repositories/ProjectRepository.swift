import Foundation
import SwiftData

enum RepositoryError: Error, Equatable {
    case emptyName
    case invalidMeasurement
    case lastFloor
}

/// Creates, updates and deletes projects, keeping database rows and on-disk files consistent.
struct ProjectRepository {
    let context: ModelContext
    let files: LocalFileStorageService

    func fetchAll() throws -> [Project] {
        try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }

    func project(id: UUID) throws -> Project? {
        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Creates a project with one default floor so rooms always have a home. The floor is stored
    /// without a name so it is always displayed with the localized default ("1-qavat", "Floor 1"…).
    @discardableResult
    func create(name: String, description: String? = nil) throws -> Project {
        let name = try validatedName(name)
        let project = Project(name: name, projectDescription: description.nilIfBlank)
        context.insert(project)
        let floor = Floor(level: 1, name: "")
        context.insert(floor)
        floor.project = project
        try context.save()
        return project
    }

    func rename(_ project: Project, to name: String) throws {
        project.name = try validatedName(name)
        project.updatedAt = .now
        try context.save()
    }

    func updateDescription(_ project: Project, to description: String?) throws {
        project.projectDescription = description.nilIfBlank
        project.updatedAt = .now
        try context.save()
    }

    /// Deletes the project (floors, rooms and asset metadata cascade), then its files.
    /// Files are removed after the database commit so metadata never points at deleted files.
    func delete(_ project: Project) throws {
        let projectID = project.id
        context.delete(project)
        try context.save()
        try files.deleteProjectDirectory(for: projectID)
    }

    /// Removes project folders on disk that no longer have a database row
    /// (e.g. if the app was terminated between the commit and the file cleanup).
    @discardableResult
    func removeOrphanedFiles() throws -> Int {
        let known = Set(try fetchAll().map(\.id))
        let orphans = files.storedProjectIDs().subtracting(known)
        for id in orphans {
            try files.deleteProjectDirectory(for: id)
        }
        return orphans.count
    }

    private func validatedName(_ name: String) throws -> String {
        guard let trimmed = name.nilIfBlank else { throw RepositoryError.emptyName }
        return trimmed
    }
}

extension Optional where Wrapped == String {
    /// Trimmed value, or nil when empty / whitespace only.
    var nilIfBlank: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

extension String {
    var nilIfBlank: String? { Optional(self).nilIfBlank }
}
