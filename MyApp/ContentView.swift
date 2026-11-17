import SwiftUI
import SwiftData

/// Root shell: header, the selected tab's content, the floating tab bar,
/// and a single navigation stack that pushes project details over everything.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var model = model
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--precision-tap-ui-test") {
            PrecisionTapUITestFixtureView()
        } else {
            appShell(model: model)
        }
        #else
        appShell(model: model)
        #endif
    }

    private func appShell(model: AppModel) -> some View {
        @Bindable var model = model
        return NavigationStack(path: $model.path) {
            VStack(spacing: 0) {
                AppHeader()
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Palette.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FloatingTabBar(selection: $model.selectedTab) {
                    model.openScanner()
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationTitle(settings.t(model.selectedTab.titleKey))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .project(let id): ProjectDetailScreen(projectID: id)
                case .reports(let id): ReportsScreen(projectID: id)
                case .savedScan(let projectID, let roomID, let scanID):
                    SavedScanViewerScreen(projectID: projectID, roomID: roomID, scanID: scanID)
                }
            }
        }
        .tint(Palette.accentText)
        .sheet(isPresented: $model.isCreatingProject) {
            NewProjectSheet()
                .toastOverlay(model, settings: settings)
        }
        .fullScreenCover(item: $model.scanner) { context in
            ScannerReadinessView(context: context)
        }
        .toastOverlay(model, settings: settings)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch model.selectedTab {
        case .home: HomeView()
        case .projects: ProjectsView()
        case .settings: SettingsView()
        }
    }
}

#Preview("Light") {
    PreviewContainer { ContentView() }
}

#Preview("Dark · Russian") {
    PreviewContainer(language: .russian) { ContentView() }
        .preferredColorScheme(.dark)
}

/// In-memory database with the sample project and temporary file storage, for previews only.
struct PreviewContainer<Content: View>: View {
    private let model = AppModel()
    private let settings: AppSettings
    private let files: LocalFileStorageService
    private let container: ModelContainer?
    private let content: Content

    init(language: AppLanguage = .english, @ViewBuilder content: () -> Content) {
        let defaults = UserDefaults(suiteName: "preview.\(UUID().uuidString)") ?? .standard
        settings = AppSettings(defaults: defaults)
        settings.language = language
        files = LocalFileStorageService(rootURL: .temporaryDirectory.appending(path: "preview-\(UUID().uuidString)"))
        container = try? Persistence.makeContainer(storeURL: nil)
        if let container {
            _ = try? SampleProjectSeeder.seedIfNeeded(context: container.mainContext, files: files,
                                                  settings: settings, defaults: defaults)
        }
        self.content = content()
    }

    var body: some View {
        if let container {
            content
                .modelContainer(container)
                .environment(model)
                .environment(settings)
                .environment(\.fileStorage, files)
        }
    }
}
