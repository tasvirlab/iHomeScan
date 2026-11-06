import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]

    @State private var renaming: Project?
    @State private var deleting: Project?

    private var otherProjects: ArraySlice<Project> { projects.dropFirst().prefix(5) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let project = projects.first {
                    SectionLabel(title: settings.t("home.continue"))
                        .padding(.top, 12)
                        .padding(.bottom, 10)

                    Button { model.open(project) } label: {
                        ContinueProjectCard(project: project)
                    }
                    .buttonStyle(.pressable)
                    .contextMenu {
                        ProjectContextMenu(project: project, renaming: $renaming, deleting: $deleting)
                    }
                    .padding(.horizontal, Spacing.screenEdge)
                } else {
                    EmptyProjectsCard()
                        .padding(.horizontal, Spacing.screenEdge)
                        .padding(.top, 12)
                }

                if !otherProjects.isEmpty {
                    SectionLabel(title: settings.t("home.otherProjects"))
                        .padding(.top, 24)
                        .padding(.bottom, 6)

                    VStack(spacing: 0) {
                        ForEach(otherProjects) { project in
                            Button { model.open(project) } label: {
                                ProjectRow(project: project)
                            }
                            .buttonStyle(.pressable)
                            .contextMenu {
                                ProjectContextMenu(project: project, renaming: $renaming, deleting: $deleting)
                            }

                            if project.id != otherProjects.last?.id {
                                Rectangle()
                                    .fill(Palette.line)
                                    .frame(height: 0.5)
                                    .padding(.leading, 76)
                            }
                        }
                    }
                    .cardSurface()
                    .padding(.horizontal, Spacing.screenEdge)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .projectActions(renaming: $renaming, deleting: $deleting)
    }
}

/// Large hero card showing the most recently updated project.
private struct ContinueProjectCard: View {
    let project: Project

    @Environment(AppSettings.self) private var settings
    @State private var plan: FloorPlan?

    private var floor: Floor? { project.sortedFloors.first { $0.planAsset != nil } }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let plan, let floor {
                    FloorPlanCanvas(plan: plan, style: .plain, labels: floor.planLabels)
                } else {
                    VStack(spacing: 10) {
                        ScanFrameGlyph(cornerColor: Palette.inkTertiary, lineWidth: 2)
                            .frame(width: 44, height: 44)
                        Text(settings.t("plan.notScanned"))
                            .font(Typography.body)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.planBackground)
                }
            }
            .padding(.bottom, 70)
            .background(Palette.planBackground)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(ProjectMeta.list(project, settings: settings))
                        .font(Typography.meta)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.accentText)
                    .frame(width: 40, height: 40)
                    .background(Palette.accentTint, in: .circle)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 14)
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .cardSurface(cornerRadius: 18)
            .padding(10)
        }
        .overlay(alignment: .topLeading) {
            if project.isSample {
                SampleBadge(onMaterial: true).padding(12)
            }
        }
        .frame(height: 400)
        .clipShape(.rect(cornerRadius: Radius.hero))
        .overlay(RoundedRectangle(cornerRadius: Radius.hero).strokeBorder(Palette.line, lineWidth: 0.5))
        .contentShape(.rect(cornerRadius: Radius.hero))
        .loadsFloorPlan(floor?.planAsset, into: $plan)
        .accessibilityElement(children: .combine)
    }
}

/// Compact list row with a plan thumbnail.
private struct ProjectRow: View {
    let project: Project
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 14) {
            PlanThumbnail(project: project)
                .padding(4)
                .frame(width: 48, height: 48)
                .background(Palette.planBackground, in: .rect(cornerRadius: Radius.small))
                .clipShape(.rect(cornerRadius: Radius.small))
                .overlay(RoundedRectangle(cornerRadius: Radius.small).strokeBorder(Palette.line, lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(ProjectMeta.list(project, settings: settings))
                    .font(Typography.meta)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Palette.inkTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
