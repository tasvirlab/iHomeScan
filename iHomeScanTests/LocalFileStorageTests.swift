import Foundation
import Testing
@testable import iHomeScan

@MainActor
@Suite("Local file storage")
struct LocalFileStorageTests {
    @Test("Files are saved under Projects/<id>/<folder> with a relative path and checksum")
    func saveAndRead() throws {
        let env = try TestEnvironment()
        let id = UUID()
        let data = Data("hello".utf8)

        let stored = try env.files.save(data, projectID: id, type: .pdfReport, preferredFileName: "report.pdf")

        #expect(stored.relativePath == "Projects/\(id.uuidString)/Reports/report.pdf")
        #expect(stored.fileSize == 5)
        #expect(stored.checksum == LocalFileStorageService.checksum(of: data))
        #expect(env.files.fileExists(atRelativePath: stored.relativePath))
        #expect(try env.files.read(relativePath: stored.relativePath, expectedChecksum: stored.checksum) == data)
    }

    @Test("Each asset type goes to its folder", arguments: [
        (AssetType.roomPlanSource, "Scans"), (.roomGeometry, "Scans"), (.usdzModel, "Models"), (.inspectionPhoto, "Photos"),
        (.projectThumbnail, "Photos"), (.pdfReport, "Reports"),
    ])
    func folders(type: AssetType, folder: String) throws {
        let env = try TestEnvironment()
        let stored = try env.files.save(Data([1]), projectID: UUID(), type: type, preferredFileName: "f.bin")
        #expect(stored.relativePath.split(separator: "/")[2] == Substring(folder))
    }

    @Test("Name collisions get a numbered suffix instead of overwriting")
    func collisions() throws {
        let env = try TestEnvironment()
        let id = UUID()
        let first = try env.files.save(Data("1".utf8), projectID: id, type: .inspectionPhoto, preferredFileName: "photo.jpg")
        let second = try env.files.save(Data("2".utf8), projectID: id, type: .inspectionPhoto, preferredFileName: "photo.jpg")

        #expect(first.fileName == "photo.jpg")
        #expect(second.fileName == "photo (2).jpg")
        #expect(try env.files.read(relativePath: first.relativePath) == Data("1".utf8))
    }

    @Test("Unsafe file names are sanitized; Uzbek and Cyrillic letters are kept")
    func sanitizing() throws {
        let env = try TestEnvironment()
        let stored = try env.files.save(Data([1]), projectID: UUID(), type: .pdfReport,
                                        preferredFileName: "../Чиланзар/Oʻzbek:report.pdf")
        #expect(!stored.fileName.contains("/"))
        #expect(stored.fileName.contains("Чиланзар"))
        #expect(env.files.fileExists(atRelativePath: stored.relativePath))
    }

    @Test("Paths escaping the storage root are rejected", arguments: ["../secret", "/etc/passwd", "Projects/../../x", ""])
    func pathTraversal(path: String) throws {
        let env = try TestEnvironment()
        #expect(throws: FileStorageError.invalidPath(path)) { try env.files.url(forRelativePath: path) }
        #expect(!env.files.fileExists(atRelativePath: path))
    }

    @Test("Missing and corrupted files are reported")
    func missingAndCorrupted() throws {
        let env = try TestEnvironment()
        let stored = try env.files.save(Data("original".utf8), projectID: UUID(), type: .roomGeometry, preferredFileName: "plan.json")

        try Data("tampered".utf8).write(to: env.files.url(forRelativePath: stored.relativePath))
        #expect(throws: FileStorageError.corrupted(stored.relativePath)) {
            try env.files.read(relativePath: stored.relativePath, expectedChecksum: stored.checksum)
        }

        try env.files.deleteFile(atRelativePath: stored.relativePath)
        #expect(throws: FileStorageError.fileMissing(stored.relativePath)) {
            try env.files.read(relativePath: stored.relativePath)
        }
        // Deleting again is a no-op.
        try env.files.deleteFile(atRelativePath: stored.relativePath)
    }

    @Test("Importing a file copies it without leaving partial files")
    func importFile() throws {
        let env = try TestEnvironment()
        let id = UUID()
        let source = env.root.appending(path: "model.usdz")
        try Data(repeating: 7, count: 1_000_000).write(to: source)

        let stored = try env.files.importFile(at: source, projectID: id, type: .usdzModel)

        #expect(stored.fileSize == 1_000_000)
        let folder = env.files.projectDirectory(for: id).appending(path: "Models")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(names == ["model.usdz"])
    }

    @Test("Asset repository stores metadata and loads plan geometry with integrity checks")
    func planAssetRoundTrip() throws {
        let env = try TestEnvironment()
        let project = try env.projects.create(name: "P")
        let floor = try #require(project.floors.first)

        let asset = try env.assets.savePlan(SampleProjectSeeder.plan, for: floor)

        #expect(asset.type == .roomGeometry)
        #expect(asset.project?.id == project.id)
        #expect(floor.planAsset?.id == asset.id)
        #expect(project.status == .scanned)
        #expect(try env.assets.loadPlan(asset) == SampleProjectSeeder.plan)

        try Data("{ not json".utf8).write(to: env.files.url(forRelativePath: asset.relativeFilePath))
        #expect(throws: FileStorageError.self) { try env.assets.loadPlan(asset) }
    }
}
