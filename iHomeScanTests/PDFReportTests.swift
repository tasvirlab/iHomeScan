import Foundation
import Testing
import PDFKit
import UIKit
@testable import iHomeScan

@MainActor
@Suite("PDF reports")
struct PDFReportTests {
    private func content(rooms: Int, name: String = "Test project") -> ReportContent {
        ReportContent(
            labels: .init(
                reportTitle: "Report", projectSection: "Project", roomsSection: "Rooms",
                roomColumns: ["Room", "Type", "Floor", "Dimensions", "Area"], noRooms: "No rooms",
                plansSection: "Plans", planUnavailable: "Floor plan unavailable", aiSection: "AI findings",
                aiPending: "No AI inspection", pageFormat: "Page %1$lld of %2$lld"
            ),
            projectName: name,
            generatedAt: "Generated now",
            info: [.init(label: "Rooms", value: "\(rooms)")],
            sampleNotice: nil,
            rooms: (0..<rooms).map { .init(name: "Room \($0)", type: "Bedroom", floor: "Floor 1", dimensions: "4,200 × 4,800 mm", area: "20.2 m²") },
            floorPlans: [.init(floorName: "Floor 1", image: nil)],
            locale: Locale(identifier: "en_US")
        )
    }

    @Test("Renders a readable single-page PDF with all sections")
    func singlePage() throws {
        let data = PDFReportService().render(content(rooms: 3))
        let document = try #require(PDFDocument(data: data))
        let text = try #require(document.string)

        #expect(document.pageCount == 1)
        for expected in ["iHomeScan", "Test project", "Room 2", "Floor plan unavailable", "AI findings", "Page 1 of 1"] {
            #expect(text.contains(expected), "missing \(expected)")
        }
    }

    @Test("Long room lists paginate with numbered pages")
    func pagination() throws {
        let data = PDFReportService().render(content(rooms: 120))
        let document = try #require(PDFDocument(data: data))
        let text = try #require(document.string)

        #expect(document.pageCount > 2)
        #expect(text.contains("Room 119"))
        #expect(text.contains("Page \(document.pageCount) of \(document.pageCount)"))
        // The table header is repeated on continuation pages.
        let secondPage = try #require(document.page(at: 1)?.string)
        #expect(secondPage.contains("Dimensions"))
    }

    @Test("Section headings are never left alone at the bottom of a page")
    func headingsStayWithContent() throws {
        let plan = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 480)).image { context in
            UIColor.lightGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 500, height: 480))
        }
        for roomCount in 1...45 {
            var report = content(rooms: roomCount)
            report = ReportContent(
                labels: report.labels, projectName: report.projectName, generatedAt: report.generatedAt,
                info: report.info, sampleNotice: report.sampleNotice, rooms: report.rooms,
                floorPlans: [.init(floorName: "Ground level", image: plan)], locale: report.locale
            )
            let document = try #require(PDFDocument(data: PDFReportService().render(report)))
            let pageText = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
            let headingPage = try #require(pageText.firstIndex { $0.contains("Plans") }, "rooms: \(roomCount)")
            #expect(pageText[headingPage].contains("Ground level"), "heading orphaned with \(roomCount) rooms")
        }
    }

    @Test("Uzbek Latin and Cyrillic text survive rendering", arguments: ["Mirzo Ulugʻbek, oʻquv xonasi", "Чиланзар 9, 2-комн."])
    func scripts(name: String) throws {
        let data = PDFReportService().render(content(rooms: 1, name: name))
        let text = TestEnvironment.normalizedPDFText(try #require(PDFDocument(data: data)?.string))
        #expect(text.contains(name))
    }

    @Test("Generator saves a localized report with the sample notice and floor plan", arguments: AppLanguage.allCases)
    func generateAndSave(language: AppLanguage) throws {
        let env = try TestEnvironment(language: language)
        let project = try #require(try SampleProjectSeeder.seedIfNeeded(
            context: env.context, files: env.files, settings: env.settings, defaults: env.defaults))

        let report = try ReportGenerator(context: env.context, files: env.files, settings: env.settings).generate(for: project)

        #expect(report.type == .pdfReport)
        #expect(project.reports.map(\.id) == [report.id])
        #expect(report.relativeFilePath.hasPrefix("Projects/\(project.id.uuidString)/Reports/"))
        let data = try env.assets.data(for: report)
        let document = try #require(PDFDocument(data: data))
        let text = TestEnvironment.normalizedPDFText(try #require(document.string))
        #expect(text.contains(TestEnvironment.normalizedPDFText(env.settings.t("report.title"))))
        #expect(text.contains(TestEnvironment.normalizedPDFText(project.name)))
        #expect(text.contains(env.settings.t("report.section.ai")))
        // Sample projects must be labelled as such in the report.
        #expect(text.contains(String(env.settings.t("report.sample.note").prefix(20))))
        // The sample floor has plan geometry, so the "unavailable" text must not appear.
        #expect(!text.contains(env.settings.t("report.plan.unavailable")))
    }

    @Test("Floors without a plan are reported as unavailable, not drawn")
    func noPlan() throws {
        let env = try TestEnvironment()
        let project = try env.projects.create(name: "Empty")

        let report = try ReportGenerator(context: env.context, files: env.files, settings: env.settings).generate(for: project)
        let text = try #require(PDFDocument(data: try env.assets.data(for: report))?.string)

        #expect(text.contains(env.settings.t("report.plan.unavailable")))
        #expect(text.contains(env.settings.t("report.noRooms")))
    }
}
