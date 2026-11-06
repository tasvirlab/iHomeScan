import SwiftUI
import SwiftData

@main struct MyApp: App {
    @State private var model = AppModel()
    @State private var settings = AppSettings()
    private let fileStorage = LocalFileStorageService.shared
    /// Nil when the store could not be opened. Data is never reset automatically.
    private let container: ModelContainer?
    private let containerError: String?

    init() {
        do {
            container = try Persistence.makeContainer()
            containerError = nil
        } catch {
            container = nil
            containerError = String(describing: error)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    ContentView()
                        .modelContainer(container)
                        .task { prepareLocalData(in: container) }
                } else {
                    StorageErrorView(details: containerError ?? "")
                }
            }
            .environment(model)
            .environment(settings)
            .environment(\.fileStorage, fileStorage)
            .environment(\.locale, settings.locale)
            .preferredColorScheme(settings.appearance.colorScheme)
        }
    }

    /// First-launch demo data and cleanup of files left behind by interrupted deletions.
    private func prepareLocalData(in container: ModelContainer) {
        let context = container.mainContext
        do {
            try SampleProjectSeeder.seedIfNeeded(context: context, files: fileStorage, settings: settings)
            try ProjectRepository(context: context, files: fileStorage).removeOrphanedFiles()
        } catch {
            model.showError(error)
        }
    }
}

/// Shown if the local database cannot be opened. Existing data is left untouched.
private struct StorageErrorView: View {
    let details: String
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(Palette.accentText)
            Text(settings.t("error.storage.title"))
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text(settings.t("error.storage.body"))
                .font(Typography.body)
                .foregroundStyle(Palette.inkSecondary)
            Text(details)
                .font(.caption2.monospaced())
                .foregroundStyle(Palette.inkTertiary)
                .lineLimit(4)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}
