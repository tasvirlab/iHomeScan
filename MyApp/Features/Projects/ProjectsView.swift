import SwiftUI
import SwiftData

struct ProjectsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]

    @State private var searchText = ""
    @State private var renaming: Project?
    @State private var deleting: Project?

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.grid),
        GridItem(.flexible(), spacing: Spacing.grid),
    ]

    private var filteredProjects: [Project] {
        guard let query = searchText.nilIfBlank else { return projects }
        return projects.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text(settings.t("tab.projects"))
                        .font(Typography.screenTitle)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { model.isCreatingProject = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Palette.accentText)
                            .frame(width: 36, height: 36)
                            .background(Palette.accentTint, in: .circle)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(settings.t("projects.new"))
                }
                .padding(.leading, Spacing.titleEdge)
                .padding(.trailing, Spacing.screenEdge)
                .padding(.top, 4)

                Button { model.path.append(.photoScanDrafts) } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "tray")
                            .font(Typography.cardTitle)
                            .foregroundStyle(Palette.accentText)
                            .frame(width: 44, height: 44)
                            .background(Palette.accentTint, in: .rect(cornerRadius: Radius.small))
                            .accessibilityHidden(true)
                        Text(settings.t("photoscan.drafts"))
                            .font(Typography.cardTitle)
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(Typography.meta)
                            .foregroundStyle(Palette.inkSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(13)
                    .cardSurface()
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("photoscan.drafts.open")
                .padding(.horizontal, Spacing.screenEdge)
                .padding(.top, 13)

                if projects.isEmpty {
                    EmptyProjectsCard()
                        .padding(.horizontal, Spacing.screenEdge)
                        .padding(.top, 16)
                } else {
                    SearchField(text: $searchText, prompt: settings.t("projects.search"))
                        .padding(.horizontal, Spacing.screenEdge)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    if filteredProjects.isEmpty {
                        Text(settings.t("projects.noResults"))
                            .font(Typography.body)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: Spacing.grid) {
                            ForEach(filteredProjects) { project in
                                Button { model.open(project) } label: {
                                    ProjectGridCard(project: project)
                                }
                                .buttonStyle(.pressable)
                                .contextMenu {
                                    ProjectContextMenu(project: project, renaming: $renaming, deleting: $deleting)
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.screenEdge)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .projectActions(renaming: $renaming, deleting: $deleting)
    }
}

/// Shown when no projects exist yet.
struct EmptyProjectsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Palette.inkTertiary, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                .frame(width: 150, height: 120)
            Text(settings.t("projects.empty.title"))
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .padding(.top, 10)
            Text(settings.t("projects.empty.body"))
                .font(Typography.body)
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: 280)
            ActionButton(title: settings.t("projects.new"), systemImage: "plus") {
                model.isCreatingProject = true
            }
            .frame(maxWidth: 240)
            .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(30)
        .frame(maxWidth: .infinity, minHeight: 420)
        .background {
            RoundedRectangle(cornerRadius: Radius.hero).fill(Palette.planBackground)
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.hero).strokeBorder(Palette.line, lineWidth: 0.5))
    }
}

/// Rounded search field matching the design's recessed surface style.
private struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.inkTertiary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .foregroundStyle(Palette.ink)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.inkTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 38)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.small))
    }
}

private struct ProjectGridCard: View {
    let project: Project
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if project.status == .scanned {
            scannedCard
        } else {
            unscannedCard
        }
    }

    private var scannedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanThumbnail(project: project)
                .frame(width: 86, height: 86)
                .frame(maxWidth: .infinity, minHeight: 118)
                .background(Palette.planBackground)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Palette.line).frame(height: 0.5)
                }
                .overlay(alignment: .topLeading) {
                    if project.isSample {
                        SampleBadge(onMaterial: true).padding(8)
                    }
                }

            details(subtitle: ProjectMeta.card(project, settings: settings), subtitleColor: Palette.inkSecondary)
        }
        .clipShape(.rect(cornerRadius: Radius.card))
        .cardSurface()
        .accessibilityElement(children: .combine)
    }

    private var unscannedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScanFrameGlyph(cornerColor: Palette.inkTertiary, lineWidth: 2)
                .frame(width: 30, height: 30)
                .frame(maxWidth: .infinity, minHeight: 118)

            details(subtitle: ProjectMeta.card(project, settings: settings),
                    subtitleColor: project.totalArea == nil ? Palette.accentText : Palette.inkSecondary)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .contentShape(.rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
    }

    private func details(subtitle: String, subtitleColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(Typography.gridTitle)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(2, reservesSpace: true)
            Text(subtitle)
                .font(Typography.meta.weight(project.status == .scanned ? .regular : .medium))
                .foregroundStyle(subtitleColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}
