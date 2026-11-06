import SwiftUI
import SwiftData
#if canImport(QuickLook) && canImport(UIKit)
import QuickLook
import UIKit
#endif

struct SavedScanViewerScreen: View {
    private enum Mode: Hashable { case plan2D, model3D }

    let projectID: UUID
    let roomID: UUID
    @Query private var scans: [SavedScan]
    @Query private var rooms: [Room]

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.fileStorage) private var files

    @State private var selectedScanID: UUID?
    @State private var mode: Mode = .plan2D
    @State private var content: SavedScanContent?
    @State private var contentCache: [UUID: SavedScanContent] = [:]
    @State private var loadError: SavedScanLoadingError?
    @State private var selectedPlanRoomID: String?

    init(projectID: UUID, roomID: UUID, scanID: UUID? = nil) {
        self.projectID = projectID
        self.roomID = roomID
        _scans = Query(
            filter: #Predicate<SavedScan> { $0.roomID == roomID && $0.projectID == projectID },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        _rooms = Query(filter: #Predicate<Room> { $0.id == roomID })
        _selectedScanID = State(initialValue: scanID)
    }

    private var room: Room? { rooms.first }
    private var selectedScan: SavedScan? {
        scans.first { $0.id == selectedScanID } ?? scans.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if scans.isEmpty {
                SavedScanEmptyState()
            } else {
                SavedScanVersionHeader(
                    scans: scans,
                    selectedScanID: Binding(
                        get: { selectedScan?.id },
                        set: { selectedScanID = $0 }
                    )
                )
                .padding(.horizontal, Spacing.screenEdge)
                .padding(.vertical, 12)

                SegmentedPill(
                    options: [
                        .init(value: .plan2D, title: settings.t("project.plan2d")),
                        .init(value: .model3D, title: settings.t("project.model3d")),
                    ],
                    selection: $mode,
                    height: 34
                )
                .padding(.horizontal, Spacing.screenEdge)
                .padding(.bottom, 12)

                viewerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(.rect(cornerRadius: Radius.large))
                    .overlay(RoundedRectangle(cornerRadius: Radius.large).strokeBorder(Palette.line, lineWidth: 0.5))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(Palette.background)
        .navigationTitle(room?.name ?? settings.t("scan.viewer.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedScanID == nil { selectedScanID = scans.first?.id }
        }
        .task(id: selectedScan?.id) { loadSelectedScan() }
    }

    @ViewBuilder
    private var viewerContent: some View {
        if let content {
            switch mode {
            case .plan2D:
                FloorPlanViewer(
                    plan: content.floorPlan,
                    labels: planLabels,
                    selectedRoomID: $selectedPlanRoomID
                )
            case .model3D:
                if let modelURL = content.modelURL {
                    SavedUSDZViewer(url: modelURL)
                } else {
                    SavedScanLoadErrorView(error: content.modelError ?? .invalidModel) {
                        if let scanID = selectedScan?.id { contentCache.removeValue(forKey: scanID) }
                        loadSelectedScan()
                    }
                }
            }
        } else if let loadError {
            SavedScanLoadErrorView(error: loadError) { loadSelectedScan() }
        } else {
            ProgressView(settings.t("scan.viewer.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.planBackground)
        }
    }

    private var planLabels: [String: PlanRoomLabel] {
        guard let room, let identifier = room.geometryIdentifier else { return [:] }
        return [identifier: PlanRoomLabel(name: room.name, area: selectedScan?.floorArea)]
    }

    private func loadSelectedScan() {
        content = nil
        loadError = nil
        guard let selectedScan else { return }
        if let cached = contentCache[selectedScan.id] {
            content = cached
            return
        }
        do {
            let loaded = try SavedScanContentLoader(context: context, files: files).load(selectedScan)
            contentCache[selectedScan.id] = loaded
            content = loaded
        } catch let error as SavedScanLoadingError {
            loadError = error
        } catch {
            loadError = .invalidGeometry
        }
    }
}

private struct SavedScanVersionHeader: View {
    let scans: [SavedScan]
    @Binding var selectedScanID: UUID?
    @Environment(AppSettings.self) private var settings

    private var selectedScan: SavedScan? { scans.first { $0.id == selectedScanID } ?? scans.first }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(settings.t("scan.viewer.version"))
                    .font(Typography.settingsHeader)
                    .foregroundStyle(Palette.inkSecondary)
                if let scan = selectedScan {
                    Text(scan.createdAt, format: .dateTime.day().month(.abbreviated).year().hour().minute().locale(settings.locale))
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.ink)
                }
            }
            Spacer(minLength: 8)
            Menu {
                Picker(settings.t("scan.viewer.version"), selection: $selectedScanID) {
                    ForEach(scans) { scan in
                        Text(scan.createdAt, format: .dateTime.day().month().year().hour().minute().locale(settings.locale))
                            .tag(UUID?.some(scan.id))
                    }
                }
            } label: {
                Label(settings.t("scan.viewer.versions", scans.count), systemImage: "clock.arrow.circlepath")
                    .font(Typography.control)
                    .foregroundStyle(Palette.accentText)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(Palette.accentTint, in: .capsule)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SavedScanEmptyState: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        ContentUnavailableView(
            settings.t("scan.viewer.empty.title"),
            systemImage: "viewfinder",
            description: Text(settings.t("scan.viewer.empty.body"))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SavedScanLoadErrorView: View {
    let error: SavedScanLoadingError
    let retry: () -> Void
    @Environment(AppSettings.self) private var settings
    var body: some View {
        ContentUnavailableView {
            Label(settings.t("scan.viewer.error.title"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(settings.t(error == .missingModel || error == .invalidModel
                            ? "scan.viewer.error.model" : "scan.viewer.error.geometry"))
        } actions: {
            Button(settings.t("scanner.retry"), action: retry).buttonStyle(.borderedProminent).tint(Palette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.planBackground)
    }
}

private struct SavedUSDZViewer: View {
    let url: URL
    @Environment(AppSettings.self) private var settings

    var body: some View {
        #if canImport(QuickLook) && canImport(UIKit)
        if QLPreviewController.canPreview(url as NSURL) {
            EmbeddedQuickLookPreview(url: url)
                .background(Palette.planBackground)
        } else {
            ContentUnavailableView(
                settings.t("scan.viewer.error.model"),
                systemImage: "cube.transparent"
            )
        }
        #else
        ContentUnavailableView(
            settings.t("scan.viewer.3d.unavailable"),
            systemImage: "cube.transparent"
        )
        #endif
    }
}

#if canImport(QuickLook) && canImport(UIKit)
private struct EmbeddedQuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        controller.reloadData()
        controller.currentPreviewItemIndex = 0
    }

    static func dismantleUIViewController(_ controller: QLPreviewController, coordinator: Coordinator) {
        controller.dataSource = nil
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif
