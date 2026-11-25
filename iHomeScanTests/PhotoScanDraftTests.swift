import Foundation
import Testing
@testable import iHomeScan

@MainActor
@Suite("Photo Scan local drafts")
struct PhotoScanDraftTests {
    @Test("New sessions on the same floor are empty and save independently")
    func independentDrafts() throws {
        try withFixture { root, source in
            let archive = PhotoScanDraftArchive(root: root)
            let project = UUID(), floor = UUID()
            let location = ScanSaveRequest(project: .existing(projectID: project), floor: .existing(floorID: floor),
                                           room: .new(name: "Office"))
            for kind in [PhotoScanMediaKind.photo, .video] {
                let context = ScannerContext(projectID: project, floorID: floor)
                let work = PhotoScanDraftArchive.workspace(for: context, temporaryRoot: root)
                let initialMedia = try work.read().media
                #expect(initialMedia.isEmpty)
                var draft = try work.append(from: source, kind: kind)
                draft.destination = location
                try archive.save(draft, context: context, workspace: work)
                work.discardWorkingCopy()
            }

            let previews = try archive.list().entries
            #expect(Set(previews.map(\.id)).count == 2)
            #expect(previews.allSatisfy { $0.context.projectID == project && $0.context.floorID == floor })
            #expect(Set(previews.compactMap(\.draft.kind)) == [.photo, .video])
        }
    }

    @Test("Legacy home and floor draft media stays readable")
    func legacyDrafts() throws {
        try withFixture { root, source in
            let project = UUID(), floor = UUID()
            let legacyName = "\(project.uuidString)-\(floor.uuidString)"
            for id in ["home", legacyName] {
                let directory = root.appending(path: "PhotoScanDrafts").appending(path: id)
                let store = PhotoScanDraftStore(directory: directory)
                _ = try store.append(from: source, kind: .photo)
                let manifest = directory.appending(path: "draft-v1.json")
                let data = try Data(contentsOf: manifest)
                let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(json["originProjectID"] == nil)
            }
            let archive = PhotoScanDraftArchive(root: root)
            let entries = try archive.list().entries
            #expect(entries.count == 2)
            let entry = try #require(entries.first { $0.id == legacyName })
            #expect(entry.context.projectID == project)
            #expect(entry.context.floorID == floor)
            let opened = try archive.entry(id: entry.id)
            let photo = try #require(opened.draft.media.first)
            let originalDirectory = root.appending(path: "PhotoScanDrafts").appending(path: legacyName)
            #expect(opened.url(for: photo) == originalDirectory.appending(path: photo.fileName))
            let bytes = try Data(contentsOf: opened.url(for: photo))
            #expect(bytes == Data([42]))
        }
    }

    @Test("Discarding a new scan keeps previously saved media and a video occupies the entire scan")
    func discardChanges() throws {
        try withFixture { root, source in
            let archive = PhotoScanDraftArchive(root: root)
            let origin = ScannerContext(projectID: nil, floorID: nil)
            let work = PhotoScanDraftArchive.workspace(for: origin, temporaryRoot: root)
            let clip = try work.append(from: source, kind: .video)
            #expect(throws: PhotoScanDraftError.incompatibleMedia) { try work.append(from: source, kind: .photo) }
            #expect(throws: PhotoScanDraftError.incompatibleMedia) { try work.append(from: source, kind: .video) }
            try archive.save(clip, context: origin, workspace: work)
            #expect(throws: PhotoScanDraftError.changedDraft) {
                try archive.save(clip, context: origin, workspace: work)
            }
            work.discardWorkingCopy()

            let anotherScan = ScannerContext(projectID: nil, floorID: nil)
            let editing = PhotoScanDraftArchive.workspace(for: anotherScan, temporaryRoot: root)
            _ = try editing.append(from: source, kind: .photo)
            editing.discardWorkingCopy()
            let entries = try archive.list().entries
            #expect(entries.count == 1)
            let archived = try #require(entries.first)
            #expect(archived.draft.media == clip.media)
            #expect(archived.draft.kind == .video)
            let savedFile = try #require(archived.draft.media.first)
            let bytes = try Data(contentsOf: archived.url(for: savedFile))
            #expect(bytes == Data([42]))
        }
    }

    @Test("Photo Scan, capture, and destination labels follow the selected app language")
    func scanLocalizations() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.language = .uzbek
        #expect(settings.t("photoscan.camera.open") == "Rasm yoki video olish")
        #expect(settings.t("photoscan.camera.record") == "Yozishni boshlash")
        #expect(settings.t("photoscan.save") == "Draftni saqlash")
        #expect(settings.t("scan.save.project") == "Loyiha")
        settings.language = .russian
        #expect(settings.t("photoscan.camera.open") == "Снять фото или видео")
        #expect(settings.t("photoscan.camera.record") == "Начать запись")
        #expect(settings.t("photoscan.save") == "Сохранить черновик")
        #expect(settings.t("scan.save.project") == "Проект")
    }

    private func withFixture(_ test: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "prepared-media")
        try Data([42]).write(to: source)
        try test(root, source)
    }
}
