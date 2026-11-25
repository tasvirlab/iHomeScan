import SwiftData
import SwiftUI

struct PhotoScanDraftsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.fileStorage) private var files
    @Query private var projects: [Project]
    @State private var entries: [PhotoScanDraftEntry] = []
    @State private var unavailable = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 13) {
                if entries.isEmpty && !unavailable {
                    ContentUnavailableView(
                        settings.t("photoscan.drafts.empty"), systemImage: "tray",
                        description: Text(settings.t("photoscan.drafts.empty.body"))
                    )
                }
                if unavailable {
                    Label(settings.t("photoscan.drafts.unreadable"), systemImage: "exclamationmark.circle")
                        .font(Typography.body)
                        .foregroundStyle(Palette.error)
                }
                ForEach(entries) { entry in
                    NavigationLink(value: Route.photoScanDraft(entry.id)) { row(entry) }
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("photoscan.draft.\(entry.id)")
                }
            }
            .padding(.horizontal, Spacing.screenEdge)
            .padding(.vertical, 21)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(settings.t("photoscan.drafts"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("photoscan.drafts.screen")
        .task {
            do {
                let result = try PhotoScanDraftArchive(root: files.rootURL).list()
                entries = result.entries
                unavailable = result.unreadable
            } catch { unavailable = true }
        }
    }

    private func row(_ entry: PhotoScanDraftEntry) -> some View {
        let name = PhotoScanLocation.label(for: entry.draft, context: entry.context, settings: settings) { id in
            projects.first { $0.id == id }
        }
        let media = entry.draft.kind == .video
            ? settings.t("photoscan.kind.video")
            : settings.t("photoscan.count", entry.draft.media.count)
        return HStack(alignment: .top, spacing: 13) {
            Image(systemName: entry.draft.kind == .video ? "video" : "photo.on.rectangle")
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.accentText)
                .frame(width: 44, height: 44)
                .background(Palette.accentTint, in: .rect(cornerRadius: Radius.small))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(name ?? settings.t("photoscan.drafts.unassigned"))
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.ink)
                Text(media).font(Typography.body).foregroundStyle(Palette.inkSecondary)
                if let date = entry.updatedAt {
                    Text(date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(settings.locale)))
                        .font(Typography.meta)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.right")
                .font(Typography.meta)
                .foregroundStyle(Palette.inkSecondary)
                .accessibilityHidden(true)
        }
        .padding(13)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

struct PhotoScanSavedDraftView: View {
    let draftID: String
    @Environment(AppSettings.self) private var settings
    @Environment(\.fileStorage) private var files
    @Query private var projects: [Project]
    @State private var entry: PhotoScanDraftEntry?
    @State private var failed = false
    @State private var previewItem: PhotoScanMedia?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                if let entry {
                    details(entry)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                        ForEach(entry.draft.media) { item in
                            Button { previewItem = item } label: {
                                PhotoScanThumbnail(url: entry.url(for: item), kind: item.kind)
                                    .frame(height: 112)
                                    .frame(maxWidth: .infinity)
                                    .background(Palette.surface)
                                    .clipShape(.rect(cornerRadius: Radius.small))
                            }
                            .buttonStyle(.pressable)
                            .accessibilityLabel(settings.t(item.kind.titleKey))
                            .accessibilityIdentifier("photoscan.saved.media")
                        }
                    }
                } else if failed {
                    ContentUnavailableView(settings.t("photoscan.loadError"), systemImage: "exclamationmark.circle")
                } else {
                    ProgressView()
                }
            }
            .padding(.horizontal, Spacing.screenEdge)
            .padding(.vertical, 21)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(settings.t("photoscan.draft.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("photoscan.draft.detail")
        .sheet(item: $previewItem) { item in
            if let entry { PhotoScanMediaPreview(item: item, url: entry.url(for: item)) }
        }
        .task(id: draftID) {
            do {
                entry = try PhotoScanDraftArchive(root: files.rootURL).entry(id: draftID)
                failed = false
            } catch { failed = true }
        }
    }

    private func details(_ entry: PhotoScanDraftEntry) -> some View {
        let name = PhotoScanLocation.label(for: entry.draft, context: entry.context, settings: settings) { id in
            projects.first { $0.id == id }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text(name ?? settings.t("photoscan.drafts.unassigned"))
                .font(Typography.detailTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if let date = entry.updatedAt {
                Text(date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(settings.locale)))
                    .font(Typography.meta)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }
}

enum PhotoScanLocation {
    static func context(for draft: PhotoScanDraft, originatingAt original: ScannerContext) -> ScannerContext {
        guard case .existing(let projectID) = draft.destination?.project else { return original }
        let floorID: UUID?
        if case .existing(let id) = draft.destination?.floor { floorID = id }
        else { floorID = nil }
        return ScannerContext(projectID: projectID, floorID: floorID)
    }

    static func label(for draft: PhotoScanDraft, context original: ScannerContext, settings: AppSettings,
                      projectForID: (UUID) -> Project?) -> String? {
        if case .new(let name) = draft.destination?.project {
            var parts = [name, settings.t("floor.defaultName", 1)]
            if case .new(let room) = draft.destination?.room { parts.append(room) }
            return parts.joined(separator: " · ")
        }
        let entry = context(for: draft, originatingAt: original)
        guard let projectID = entry.projectID, let project = projectForID(projectID) else { return nil }
        var parts = [project.name]
        if draft.destination?.floor == .new {
            parts.append(settings.t("floor.defaultName", (project.floors.map(\.level).max() ?? 0) + 1))
        }
        if let floor = project.floors.first(where: { $0.id == entry.floorID }) {
            parts.append(settings.floorName(floor))
            if case .existing(let roomID) = draft.destination?.room,
               let room = floor.rooms.first(where: { $0.id == roomID }) { parts.append(room.name) }
        }
        if case .new(let room) = draft.destination?.room { parts.append(room) }
        return parts.joined(separator: " · ")
    }
}
