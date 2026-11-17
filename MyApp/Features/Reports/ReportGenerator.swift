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
        let precisionDocuments = authoritativePrecisionDocuments(for: project)
        let authoritativeAreas = Dictionary(uniqueKeysWithValues: rooms.compactMap { room in
            let area = PrecisionAreaPolicy.authoritativeArea(
                precisionPlan: precisionDocuments[room.id]?.currentPlan,
                storedArea: room.effectiveArea
            )
            return area.map { (room.id, $0) }
        })
        let authoritativeTotal = authoritativeAreas.isEmpty ? nil : rooms.reduce(0) {
            $0 + (authoritativeAreas[$1.id] ?? 0)
        }
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
            .init(label: t("report.field.totalArea"), value: authoritativeTotal.map(settings.area) ?? t("report.notMeasured")),
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
                    area: authoritativeAreas[room.id].map(settings.area) ?? dash
                )
            }
        }

        let assets = AssetRepository(context: context, files: files)
        let plans = floors.map { floor in
            let plan = floor.planAsset.flatMap { try? assets.loadPlan($0) }
            let floorRooms = floor.sortedRooms
            let precisionPlan = floorRooms.lazy.compactMap { precisionDocuments[$0.id]?.currentPlan }.first
            let labels = Dictionary(uniqueKeysWithValues: floor.planLabels.map { key, value in
                let room = floorRooms.first { $0.geometryIdentifier == key }
                return (key, PlanRoomLabel(name: value.name, area: room.flatMap { authoritativeAreas[$0.id] } ?? value.area))
            })
            return ReportContent.FloorPlanSection(
                floorName: settings.floorName(floor),
                image: plan.flatMap { renderPlanImage($0, labels: labels, precisionPlan: precisionPlan) }
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

    private func authoritativePrecisionDocuments(for project: Project) -> [UUID: PrecisionPlanDocument] {
        guard let scans = try? context.fetch(FetchDescriptor<SavedScan>()) else { return [:] }
        let latest = scans
            .filter { $0.projectID == project.id }
            .sorted { $0.createdAt > $1.createdAt }
            .reduce(into: [UUID: SavedScan]()) { result, scan in
                if result[scan.roomID] == nil { result[scan.roomID] = scan }
            }
        return latest.reduce(into: [:]) { result, entry in
            let scan = entry.value
            guard files.precisionPlanExists(projectID: scan.projectID, scanID: scan.id),
                  let data = try? files.readPrecisionPlan(projectID: scan.projectID, scanID: scan.id),
                  let document = try? PrecisionPlanDocument.decode(from: data) else { return }
            result[entry.key] = document
        }
    }

    /// Draws the stored plan geometry with the same canvas used in the app, in light mode.
    private func renderPlanImage(
        _ plan: FloorPlan,
        labels: [String: PlanRoomLabel],
        precisionPlan: ParametricFloorPlan?
    ) -> UIImage? {
        let aspect = (plan.bounds.height + 2.35) / max(plan.bounds.width + 2.3, 0.1)
        let width: CGFloat = 500
        let view = FloorPlanCanvas(
            plan: plan,
            style: .draft,
            labels: labels,
            showsGrid: false,
            precisionPlan: precisionPlan
        )
            .frame(width: width, height: width * aspect)
            .environment(settings)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}
