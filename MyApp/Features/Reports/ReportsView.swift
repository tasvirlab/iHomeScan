import SwiftUI
import SwiftData
import PDFKit

struct ReportsScreen: View {
    @Query private var results: [Project]

    init(projectID: UUID) {
        _results = Query(filter: #Predicate<Project> { $0.id == projectID })
    }

    var body: some View {
        if let project = results.first {
            ReportsView(project: project)
        } else {
            MissingProjectView()
        }
    }
}

/// Generates real PDF reports for a project and lists the ones saved on this device.
struct ReportsView: View {
    let project: Project

    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.fileStorage) private var files

    @State private var isGenerating = false
    @State private var previewing: PreviewItem?
    @State private var deleting: LocalAsset?

    struct PreviewItem: Identifiable {
        let id: UUID
        let url: URL
        let title: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.t("project.pdf"))
                        .font(Typography.screenTitle)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: "\(settings.t("report.format")) · \(project.name)")
                        .font(Typography.body)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.horizontal, Spacing.titleEdge)
                .padding(.top, 4)
                .padding(.bottom, 16)

                summaryCard
                    .padding(.horizontal, Spacing.screenEdge)

                ActionButton(
                    title: settings.t(isGenerating ? "report.generating" : "report.generate"),
                    systemImage: "doc.badge.plus",
                    isLoading: isGenerating,
                    action: generate
                )
                .padding(.horizontal, Spacing.screenEdge)
                .padding(.top, 16)

                SectionLabel(title: settings.t("report.saved"))
                    .padding(.top, 26)
                    .padding(.bottom, 8)

                if project.reports.isEmpty {
                    Text(settings.t("report.saved.empty"))
                        .font(Typography.body)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, Spacing.titleEdge)
                } else {
                    VStack(spacing: 0) {
                        ForEach(project.reports) { report in
                            reportRow(report)
                            if report.id != project.reports.last?.id {
                                Rectangle().fill(Palette.line).frame(height: 0.5).padding(.leading, 70)
                            }
                        }
                    }
                    .cardSurface()
                    .padding(.horizontal, Spacing.screenEdge)
                }
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background)
        .navigationTitle(settings.t("project.pdf"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
        }
        .sheet(item: $previewing) { item in
            PDFPreviewSheet(url: item.url, title: item.title)
                .toastOverlay(model, settings: settings)
        }
        .confirmationDialog(
            settings.t("report.delete.title"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { report in
            Button(settings.t("common.delete"), role: .destructive) {
                do { try AssetRepository(context: context, files: files).delete(report) } catch { model.showError(error) }
                deleting = nil
            }
            Button(settings.t("common.cancel"), role: .cancel) { deleting = nil }
        } message: { report in
            Text(report.fileName)
        }
    }

    /// What the report will contain, so users know before generating.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryRow("report.field.floors", value: "\(project.floors.count)")
            summaryRow("report.field.rooms", value: "\(project.allRooms.count)")
            summaryRow("report.field.totalArea", value: project.totalArea.map(settings.area) ?? settings.t("report.notMeasured"))
            if project.isSample {
                HStack(spacing: 8) {
                    SampleBadge()
                    Text(settings.t("report.sample.short"))
                        .font(Typography.meta)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func summaryRow(_ key: String, value: String) -> some View {
        HStack {
            Text(settings.t(key))
                .font(Typography.body)
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            Text(value)
                .font(Typography.measurementEmphasis)
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func reportRow(_ report: LocalAsset) -> some View {
        let exists = files.fileExists(atRelativePath: report.relativeFilePath)
        return HStack(spacing: 12) {
            Text(verbatim: "PDF")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 38, height: 48)
                .background(Color.white, in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line, lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(report.fileName)
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(exists
                     ? "\(settings.shortDate(report.createdAt)) · \(ByteCountFormatter.string(fromByteCount: report.fileSize, countStyle: .file))"
                     : settings.t("error.fileMissing"))
                    .font(Typography.meta)
                    .foregroundStyle(exists ? Palette.inkSecondary : Palette.error)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if exists, let url = try? files.url(forRelativePath: report.relativeFilePath) {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.accentText)
                        .frame(width: 36, height: 36)
                        .background(Palette.accentTint, in: .circle)
                }
                .accessibilityLabel(settings.t("report.share"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)
        .onTapGesture { preview(report) }
        .contextMenu {
            Button(settings.t("report.preview"), systemImage: "eye") { preview(report) }
            Button(settings.t("common.delete"), systemImage: "trash", role: .destructive) { deleting = report }
        }
        .accessibilityAddTraits(.isButton)
    }

    private func preview(_ report: LocalAsset) {
        do {
            let url = try files.url(forRelativePath: report.relativeFilePath)
            guard files.fileExists(atRelativePath: report.relativeFilePath) else {
                throw FileStorageError.fileMissing(report.relativeFilePath)
            }
            previewing = PreviewItem(id: report.id, url: url, title: report.fileName)
        } catch {
            model.showError(error)
        }
    }

    private func generate() {
        guard !isGenerating else { return }
        isGenerating = true
        Task {
            // Let the button show its progress state before the synchronous rendering work starts.
            await Task.yield()
            defer { isGenerating = false }
            do {
                let report = try ReportGenerator(context: context, files: files, settings: settings).generate(for: project)
                model.showToast("toast.reportReady")
                preview(report)
            } catch {
                model.showError(error)
            }
        }
    }
}

/// Native PDF preview with a share button.
struct PDFPreviewSheet: View {
    let url: URL
    let title: String

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .background(Palette.surface)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(settings.t("common.done")) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(settings.t("report.share"))
                    }
                }
        }
        .tint(Palette.accentText)
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
