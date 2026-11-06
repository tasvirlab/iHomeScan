import SwiftUI
import SwiftData

/// Builds localized report content from a project, renders the PDF and stores it as a `.pdfReport` asset.
struct ReportGenerator {
    let context: ModelContext
    let files: LocalFileStorageService
    let settings: AppSettings

    /// Generates the PDF, saves it under the project's `Reports/` folder and records its metadata.
    @discardableResult
    func generate(for project: Project, date: Date = .now) throws -> LocalAsset {
        let data = PDFReportService().render(makeContent(for: project, date: date))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let stamp = formatter.string(from: date)
        return try AssetRepository(context: context, files: files).addAsset(
            data, type: .pdfReport, fileName: "iHomeScan-\(project.name)-\(stamp).pdf", project: project
        )
    }

    func makeContent(for project: Project, date: Date = .now) -> ReportContent {
        func t(_ key: String) -> String { settings.t(key) }
        let floors = project.sortedFloors
        let rooms = project.allRooms
        let dash = "—"

        var info: [ReportContent.InfoRow] = [
            .init(label: t("report.field.name"), value: project.name),
        ]
        if let description = project.projectDescription {
            info.append(.init(label: t("report.field.description"), value: description))
        }
        info += [
            .init(label: t("report.field.floors"), value: floors.count.formatted(.number.locale(settings.locale))),
            .init(label: t("report.field.rooms"), value: rooms.count.formatted(.number.locale(settings.locale))),
            .init(label: t("report.field.totalArea"), value: project.totalArea.map(settings.area) ?? t("report.notMeasured")),
        ]
        if let height = project.ceilingHeight {
            info.append(.init(label: t("report.field.ceiling"), value: settings.ceilingHeight(height)))
        }

        let roomRows = floors.flatMap { floor in
            floor.sortedRooms.map { room in
                ReportContent.RoomRow(
                    name: room.name,
                    type: room.type.map { t($0.titleKey) } ?? dash,
                    floor: settings.floorName(floor),
                    dimensions: settings.dimensions(width: room.width, length: room.length) ?? t("room.notScanned"),
                    area: room.effectiveArea.map(settings.area) ?? dash
                )
            }
        }

        let assets = AssetRepository(context: context, files: files)
        let plans = floors.map { floor in
            let plan = floor.planAsset.flatMap { try? assets.loadPlan($0) }
            return ReportContent.FloorPlanSection(
                floorName: settings.floorName(floor),
                image: plan.flatMap { renderPlanImage($0, labels: floor.planLabels) }
            )
        }

        let dateText = date.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(settings.locale))
        return ReportContent(
            labels: .init(
                reportTitle: t("report.title"),
                projectSection: t("report.section.project"),
                roomsSection: t("report.section.rooms"),
                roomColumns: [t("report.column.room"), t("report.column.type"), t("report.column.floor"),
                              t("report.column.dimensions"), t("report.column.area")],
                noRooms: t("report.noRooms"),
                plansSection: t("report.section.plans"),
                planUnavailable: t("report.plan.unavailable"),
                aiSection: t("report.section.ai"),
                aiPending: t("report.ai.pending"),
                pageFormat: t("report.page")
            ),
            projectName: project.name,
            generatedAt: settings.t("report.generated", dateText),
            info: info,
            sampleNotice: project.isSample ? t("report.sample.note") : nil,
            rooms: roomRows,
            floorPlans: plans,
            locale: settings.locale
        )
    }

    /// Draws the stored plan geometry with the same canvas used in the app, in light mode.
    private func renderPlanImage(_ plan: FloorPlan, labels: [String: PlanRoomLabel]) -> UIImage? {
        let aspect = (plan.bounds.height + 2.35) / max(plan.bounds.width + 2.3, 0.1)
        let width: CGFloat = 500
        let view = FloorPlanCanvas(plan: plan, style: .draft, labels: labels, showsGrid: false)
            .frame(width: width, height: width * aspect)
            .environment(settings)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}
