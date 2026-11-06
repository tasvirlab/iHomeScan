import Foundation
import SwiftData
@testable import iHomeScan

/// Isolated database, file storage and preferences for one test. Never touches real user data.
@MainActor
final class TestEnvironment {
    let root: URL
    let files: LocalFileStorageService
    let defaults: UserDefaults
    let settings: AppSettings
    private(set) var container: ModelContainer

    var context: ModelContext { container.mainContext }
    var projects: ProjectRepository { ProjectRepository(context: context, files: files) }
    var rooms: RoomRepository { RoomRepository(context: context, files: files) }
    var assets: AssetRepository { AssetRepository(context: context, files: files) }

    /// - Parameter onDisk: store the database in the temporary directory (for restart tests).
    init(onDisk: Bool = false, language: AppLanguage = .english) throws {
        root = URL.temporaryDirectory.appending(path: "iHomeScanTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        files = LocalFileStorageService(rootURL: root.appending(path: "Files", directoryHint: .isDirectory))
        defaults = UserDefaults(suiteName: "iHomeScanTests-\(UUID().uuidString)")!
        settings = AppSettings(defaults: defaults)
        settings.language = language
        container = try Persistence.makeContainer(storeURL: onDisk ? root.appending(path: "test.store") : nil)
    }

    var storeURL: URL { root.appending(path: "test.store") }

    /// Simulates an app restart by opening a fresh container on the same on-disk store.
    func reopen() throws {
        container = try Persistence.makeContainer(storeURL: storeURL)
    }

    func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    /// PDF text extraction maps some glyphs shared between scripts to a different code point
    /// (e.g. Cyrillic "к" → U+0138, U+2011 non-breaking hyphen → "-"). The rendered page is correct;
    /// tests compare text after folding these back.
    static func normalizedPDFText(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{0138}", with: "к")
            .replacingOccurrences(of: "\u{2011}", with: "-")
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}
