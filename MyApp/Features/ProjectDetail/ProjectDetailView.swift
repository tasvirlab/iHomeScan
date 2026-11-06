import SwiftUI
import SwiftData

/// Resolves a project by ID so the screen stays valid while data changes underneath it.
struct ProjectDetailScreen: View {
    @Query private var results: [Project]

    init(projectID: UUID) {
        _results = Query(filter: #Predicate<Project> { $0.id == projectID })
    }

    var body: some View {
        if let project = results.first {
            ProjectDetailView(project: project)
        } else {
            MissingProjectView()
        }
    }
}

struct ProjectDetailView: View {
    let project: Project

    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    private enum Mode: Hashable { case plan2D, model3D }

    @State private var mode: Mode = .plan2D
    @State private var selectedFloorID: UUID?
    @State private var selectedRoomID: String?
    @State private var plan: FloorPlan?
    @State private var planError: Error?
    @State private var showsRooms = false
    @State private var renaming: Project?
    @State private var deleting: Project?

    private var selectedFloor: Floor? {
        project.floors.first { $0.id == selectedFloorID } ?? project.sortedFloors.first
    }

    private var metaText: String {
        var parts: [String] = []
        if let area = project.totalArea { parts.append(settings.area(area)) }
        parts.append(settings.roomCount(project.allRooms.count))
        if let height = project.ceilingHeight {
            parts.append(settings.t("project.ceiling", settings.ceilingHeight(height)))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock

            FloorBar(project: project, selectedFloorID: $selectedFloorID)
                .padding(.bottom, 12)

            if plan != nil {
                SegmentedPill(
                    options: [
                        .init(value: .plan2D, title: settings.t("project.plan2d")),
                        .init(value: .model3D, title: settings.t("project.model3d")),
                    ],
                    selection: $mode,
                    height: 32
                )
                .padding(.horizontal, Spacing.titleEdge)
                .padding(.bottom, 12)
            }

            planArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: Radius.large))
                .overlay(RoundedRectangle(cornerRadius: Radius.large).strokeBorder(Palette.line, lineWidth: 0.5))
                .padding(.horizontal, 12)

            actionBar
        }
        .background(Palette.background)
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .loadsFloorPlan(selectedFloor?.planAsset, into: $plan, error: $planError)
        .onAppear {
            if selectedFloorID == nil { selectedFloorID = project.sortedFloors.first?.id }
        }
        .onChange(of: selectedFloorID) {
            selectedRoomID = nil
            mode = .plan2D
        }
        .sheet(isPresented: $showsRooms) {
            if let floor = selectedFloor {
                RoomsSheet(floor: floor, selectedRoomID: $selectedRoomID)
                    .toastOverlay(model, settings: settings)
            }
        }
        .projectActions(renaming: $renaming, deleting: $deleting) {
            model.path.removeAll { $0 == .project(project.id) || $0 == .reports(project.id) }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.name)
                .font(Typography.detailTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                Text(metaText)
                    .font(Typography.body)
                    .foregroundStyle(Palette.inkSecondary)
                if project.isSample {
                    SampleBadge()
                }
            }
            if let description = project.projectDescription {
                Text(description)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, Spacing.titleEdge)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var planArea: some View {
        if let plan, let floor = selectedFloor {
            switch mode {
            case .plan2D:
                FloorPlanViewer(plan: plan, labels: floor.planLabels, selectedRoomID: $selectedRoomID)
            case .model3D:
                PlanPlaceholder(systemImage: "cube.transparent",
                                titleKey: "project.3d.title", bodyKey: "project.3d.body")
            }
        } else if planError != nil {
            PlanPlaceholder(systemImage: "exclamationmark.triangle",
                            titleKey: "plan.error.title", bodyKey: "plan.error.body")
        } else {
            PlanPlaceholder(systemImage: nil, titleKey: "plan.notScanned", bodyKey: "plan.notScanned.body")
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(settings.t("project.pdf"), systemImage: "doc.text") {
                model.path.append(.reports(project.id))
            }
            Button(settings.t("project.rescan"), systemImage: "viewfinder") {
                model.showToast("toast.scanLater")
            }
            Button(settings.t("project.rename"), systemImage: "pencil") {
                renaming = project
            }
            Divider()
            Button(settings.t("project.delete"), systemImage: "trash", role: .destructive) {
                deleting = project
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(Palette.ink)
        }
        .accessibilityLabel(settings.t("project.more"))
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button { showsRooms = true } label: {
                Text(verbatim: "\(settings.t("project.rooms")) · \(selectedFloor?.rooms.count ?? 0)")
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 52)
                    .background(Palette.surface, in: .rect(cornerRadius: Radius.medium))
            }
            .buttonStyle(.pressable)

            Button { model.path.append(.reports(project.id)) } label: {
                Label(settings.t("project.pdf"), systemImage: "doc.text")
                    .font(Typography.button)
                    .foregroundStyle(Palette.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Palette.accent, in: .rect(cornerRadius: Radius.medium))
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

/// Centered icon + message inside the plan area (not scanned, 3D placeholder, load error).
private struct PlanPlaceholder: View {
    let systemImage: String?
    let titleKey: String
    let bodyKey: String
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Palette.inkTertiary)
            } else {
                ScanFrameGlyph(cornerColor: Palette.inkTertiary, lineWidth: 2)
                    .frame(width: 44, height: 44)
            }
            Text(settings.t(titleKey))
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text(settings.t(bodyKey))
                .font(Typography.body)
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: 270)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.planBackground)
    }
}

/// Shown if a pushed project no longer exists (e.g. deleted elsewhere).
struct MissingProjectView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Text(settings.t("project.missing"))
            .font(Typography.body)
            .foregroundStyle(Palette.inkSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
    }
}
