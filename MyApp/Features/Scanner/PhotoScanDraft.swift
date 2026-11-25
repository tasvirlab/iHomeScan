import Foundation

enum PhotoScanMediaKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case photo, video
    var id: Self { self }
    var titleKey: String { "photoscan.kind.\(rawValue)" }
    nonisolated var fileExtension: String { self == .photo ? "jpg" : "mov" }
}

enum PhotoScanDraftError: Error, Equatable {
    case incompatibleMedia, videoTooLong, unreadableMedia, missingDraft, changedDraft
}

struct PhotoScanMedia: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: PhotoScanMediaKind
    var fileName: String { "\(id.uuidString).\(kind.fileExtension)" }
}

struct PhotoScanDraft: Codable, Equatable {
    var media: [PhotoScanMedia] = []
    var destination: ScanSaveRequest?
    var originProjectID: UUID?
    var originFloorID: UUID?
    var kind: PhotoScanMediaKind? { media.first?.kind }

    func accepts(_ kind: PhotoScanMediaKind) -> Bool {
        media.isEmpty || (self.kind == .photo && kind == .photo)
    }
}

/// File storage for one working or saved draft.
struct PhotoScanDraftStore {
    let directory: URL
    private var manifest: URL { directory.appending(path: "draft-v1.json") }
    private let files = FileManager.default

    init(directory: URL) { self.directory = directory }

    var modificationDate: Date? {
        try? manifest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func read() throws -> PhotoScanDraft {
        guard files.fileExists(atPath: manifest.path) else { return PhotoScanDraft() }
        let draft = try JSONDecoder().decode(PhotoScanDraft.self, from: Data(contentsOf: manifest))
        guard draft.media.allSatisfy({ files.fileExists(atPath: url(for: $0).path) }) else {
            throw PhotoScanDraftError.missingDraft
        }
        return draft
    }

    func url(for item: PhotoScanMedia) -> URL { directory.appending(path: item.fileName) }

    func append(from source: URL, kind: PhotoScanMediaKind) throws -> PhotoScanDraft {
        var draft = try read()
        guard draft.accepts(kind) else { throw PhotoScanDraftError.incompatibleMedia }
        try prepareDirectory()
        let item = PhotoScanMedia(id: UUID(), kind: kind)
        let target = url(for: item)
        draft.media.append(item)
        do {
            try files.copyItem(at: source, to: target)
            #if os(iOS)
            try files.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                   ofItemAtPath: target.path)
            #endif
            try write(draft)
        } catch {
            try? files.removeItem(at: target)
            throw error
        }
        return draft
    }

    func remove(_ item: PhotoScanMedia) throws -> PhotoScanDraft {
        var draft = try read()
        guard let index = draft.media.firstIndex(of: item) else { return draft }
        draft.media.remove(at: index)
        if draft.media.isEmpty { draft.destination = nil }
        try write(draft)
        try? files.removeItem(at: url(for: item))
        return draft
    }

    /// Publish the manifest last. File copies that fail leave the previous draft readable.
    func replace(with draft: PhotoScanDraft, from source: PhotoScanDraftStore) throws {
        guard !draft.media.isEmpty else { throw PhotoScanDraftError.missingDraft }
        try prepareDirectory()
        var copied: [URL] = []
        do {
            for item in draft.media {
                let target = url(for: item)
                if !files.fileExists(atPath: target.path) {
                    copied.append(target)
                    try files.copyItem(at: source.url(for: item), to: target)
                }
            }
            try write(draft)
        } catch {
            for file in copied { try? files.removeItem(at: file) }
            throw error
        }
        removeUnreferencedMedia(keeping: Set(draft.media.map(\.fileName)))
    }

    func discardWorkingCopy() {
        try? files.removeItem(at: directory)
    }

    private func prepareDirectory() throws {
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        var root = directory.deletingLastPathComponent()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
    }

    private func write(_ draft: PhotoScanDraft) throws {
        try JSONEncoder().encode(draft).write(
            to: manifest, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private func removeUnreferencedMedia(keeping fileNames: Set<String>) {
        let contents = try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in contents ?? [] where ["jpg", "mov"].contains(file.pathExtension) {
            if !fileNames.contains(file.lastPathComponent) { try? files.removeItem(at: file) }
        }
    }
}

struct PhotoScanDraftEntry: Identifiable {
    let id: String
    let draft: PhotoScanDraft
    let updatedAt: Date?
    let context: ScannerContext
    let directory: URL

    func url(for item: PhotoScanMedia) -> URL { directory.appending(path: item.fileName) }
}

struct PhotoScanDraftArchive {
    let root: URL
    private var directory: URL { root.appending(path: "PhotoScanDrafts", directoryHint: .isDirectory) }

    static func workspace(for context: ScannerContext, temporaryRoot: URL = FileManager.default.temporaryDirectory)
        -> PhotoScanDraftStore {
        PhotoScanDraftStore(directory: temporaryRoot.appending(path: "PhotoScanWorking", directoryHint: .isDirectory)
            .appending(path: context.id.uuidString, directoryHint: .isDirectory))
    }

    func entry(id: String) throws -> PhotoScanDraftEntry {
        guard let legacy = Self.parse(id),
              let entry = try readEntry(id: id, legacy: legacy) else {
            throw PhotoScanDraftError.missingDraft
        }
        return entry
    }

    func save(_ draft: PhotoScanDraft, context: ScannerContext, workspace: PhotoScanDraftStore) throws {
        let target = draftStore(id: "scan-\(context.id.uuidString)")
        let current = try target.read()
        guard current.media.isEmpty else { throw PhotoScanDraftError.changedDraft }
        var published = draft
        published.originProjectID = context.projectID
        published.originFloorID = context.floorID
        try target.replace(with: published, from: workspace)
    }

    /// Legacy directory names encode the entry point. Read those files in place to preserve existing drafts.
    func list() throws -> (entries: [PhotoScanDraftEntry], unreadable: Bool) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return ([], false) }
        let paths = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var entries: [PhotoScanDraftEntry] = []
        var unreadable = false
        for path in paths {
            let id = path.lastPathComponent
            guard let legacy = Self.parse(id) else { continue }
            do {
                if let entry = try readEntry(id: id, legacy: legacy) { entries.append(entry) }
            } catch { unreadable = true }
        }
        entries.sort { ($0.updatedAt ?? .distantPast, $0.id) > ($1.updatedAt ?? .distantPast, $1.id) }
        return (entries, unreadable)
    }

    private func readEntry(id: String, legacy: (projectID: UUID?, floorID: UUID?)) throws -> PhotoScanDraftEntry? {
        let source = draftStore(id: id)
        let draft = try source.read()
        guard !draft.media.isEmpty else { return nil }
        let context = ScannerContext(projectID: draft.originProjectID ?? legacy.projectID,
                                     floorID: draft.originFloorID ?? legacy.floorID)
        return PhotoScanDraftEntry(id: id, draft: draft, updatedAt: source.modificationDate,
                                   context: context, directory: source.directory)
    }

    private func draftStore(id: String) -> PhotoScanDraftStore {
        PhotoScanDraftStore(directory: directory.appending(path: id, directoryHint: .isDirectory))
    }

    private static func parse(_ id: String) -> (projectID: UUID?, floorID: UUID?)? {
        if id == "home" { return (nil, nil) }
        if id.hasPrefix("scan-"), UUID(uuidString: String(id.dropFirst(5))) != nil { return (nil, nil) }
        if let projectID = UUID(uuidString: id) { return (projectID, nil) }
        guard id.count == 73, id.dropFirst(36).first == "-",
              let projectID = UUID(uuidString: String(id.prefix(36))),
              let floorID = UUID(uuidString: String(id.suffix(36))) else { return nil }
        return (projectID, floorID)
    }
}
