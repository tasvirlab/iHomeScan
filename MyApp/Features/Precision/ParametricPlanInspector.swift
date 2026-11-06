import SwiftUI

struct ParametricPlanInspectorScreen: View {
    let scan: SavedScan
    let floorPlan: FloorPlan

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fileStorage) private var files

    @State private var plan: ParametricFloorPlan?
    @State private var selectedWallID: UUID?
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if let plan {
                    ParametricInspectorContent(
                        plan: plan,
                        selectedWallID: $selectedWallID
                    )
                } else if loadFailed {
                    ContentUnavailableView(
                        settings.t("precision.editor.error.title"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(settings.t("precision.editor.error.body"))
                    )
                } else {
                    ProgressView(settings.t("scan.viewer.loading"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
            .navigationTitle(settings.t("precision.editor.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.t("common.done")) { dismiss() }
                }
            }
        }
        .task(id: scan.id) { loadPlan() }
    }

    private func loadPlan() {
        do {
            plan = try ParametricPlanRepository(files: files)
                .loadOrCreate(scan: scan, floorPlan: floorPlan)
            selectedWallID = plan?.walls.first?.id
        } catch {
            loadFailed = true
        }
    }
}

private struct ParametricInspectorContent: View {
    let plan: ParametricFloorPlan
    @Binding var selectedWallID: UUID?
    @Environment(AppSettings.self) private var settings

    private var selectedWall: ParametricWall? {
        selectedWallID.flatMap(plan.wall)
    }

    var body: some View {
        VStack(spacing: 0) {
            if plan.completeness != .complete {
                ParametricIncompleteBanner()
                    .padding(.horizontal, Spacing.screenEdge)
                    .padding(.vertical, 10)
            }

            ParametricWallCanvas(
                vertices: plan.vertices,
                walls: plan.walls,
                selectedWallID: $selectedWallID
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.planBackground)
            .clipShape(.rect(cornerRadius: Radius.large))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large)
                    .strokeBorder(Palette.line, lineWidth: 0.5)
            )
            .padding(.horizontal, 12)

            if let selectedWall {
                ParametricWallMetadataCard(wall: selectedWall, plan: plan)
                    .padding(12)
            } else {
                Text(settings.t("precision.editor.selectWall"))
                    .font(Typography.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding()
            }
        }
    }
}

private struct ParametricIncompleteBanner: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.accentText)
            VStack(alignment: .leading, spacing: 3) {
                Text(settings.t("precision.editor.incomplete.title"))
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.ink)
                Text(settings.t("precision.editor.incomplete.body"))
                    .font(Typography.meta)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.accentTint, in: .rect(cornerRadius: Radius.medium))
    }
}

private struct ParametricWallMetadataCard: View {
    let wall: ParametricWall
    let plan: ParametricFloorPlan
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(settings.t("precision.editor.wallDetails"))
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.ink)
            HStack(spacing: 8) {
                metric("precision.wall.length", value: wall.length(in: plan))
                metric("precision.wall.height", value: wall.height?.value)
                metric("precision.wall.thickness", value: wall.thickness?.value)
            }
            Divider()
            HStack {
                Label(settings.t("precision.source.lidar"), systemImage: "viewfinder")
                Spacer()
                Text(settings.t("precision.verification.estimated"))
            }
            .font(Typography.meta)
            .foregroundStyle(Palette.inkSecondary)
        }
        .padding(14)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large)
                .strokeBorder(Palette.line, lineWidth: 0.5)
        )
    }

    private func metric(_ key: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(settings.t(key))
                .font(Typography.meta)
                .foregroundStyle(Palette.inkSecondary)
            Text(value.map(settings.lengthValue) ?? settings.t("scan.result.measurements.unavailable"))
                .font(Typography.control.monospacedDigit())
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ParametricWallCanvas: View {
    let vertices: [PlanVertex]
    let walls: [ParametricWall]
    @Binding var selectedWallID: UUID?
    @Environment(AppSettings.self) private var settings

    private var vertexMap: [UUID: PlanVertex] {
        Dictionary(uniqueKeysWithValues: vertices.map { ($0.id, $0) })
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let transform = drawingTransform(in: size)
                for wall in walls {
                    guard let segment = segment(for: wall, transform: transform) else { continue }
                    var path = Path()
                    path.move(to: segment.start)
                    path.addLine(to: segment.end)
                    let selected = wall.id == selectedWallID
                    context.stroke(
                        path,
                        with: .color(selected ? Palette.accent : Palette.wall),
                        style: StrokeStyle(
                            lineWidth: selected ? 8 : 5,
                            lineCap: .square,
                            lineJoin: .miter
                        )
                    )
                }
            }
            .contentShape(.rect)
            .onTapGesture(coordinateSpace: .local) { location in
                selectWall(at: location, in: proxy.size)
            }
        }
        .accessibilityLabel(settings.t("precision.editor.canvas"))
    }

    private func selectWall(at point: CGPoint, in size: CGSize) {
        let transform = drawingTransform(in: size)
        let closest = walls.compactMap { wall -> (UUID, CGFloat)? in
            guard let segment = segment(for: wall, transform: transform) else { return nil }
            return (wall.id, distance(point, to: segment))
        }.min { $0.1 < $1.1 }
        selectedWallID = closest.flatMap { $0.1 <= 28 ? $0.0 : nil }
    }

    private func drawingTransform(in size: CGSize) -> CGAffineTransform {
        let points = vertices.map(\.position).filter(\.isFinite)
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else {
            return .identity
        }
        let width = max(maxX - minX, 0.1)
        let height = max(maxY - minY, 0.1)
        let scale = min(max(size.width - 56, 1) / width, max(size.height - 56, 1) / height)
        return CGAffineTransform.identity
            .translatedBy(x: size.width / 2, y: size.height / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -(minX + maxX) / 2, y: -(minY + maxY) / 2)
    }

    private func segment(
        for wall: ParametricWall,
        transform: CGAffineTransform
    ) -> (start: CGPoint, end: CGPoint)? {
        guard let start = vertexMap[wall.startVertexID]?.position,
              let end = vertexMap[wall.endVertexID]?.position else { return nil }
        return (
            CGPoint(x: start.x, y: start.y).applying(transform),
            CGPoint(x: end.x, y: end.y).applying(transform)
        )
    }

    private func distance(
        _ point: CGPoint,
        to segment: (start: CGPoint, end: CGPoint)
    ) -> CGFloat {
        let dx = segment.end.x - segment.start.x
        let dy = segment.end.y - segment.start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - segment.start.x, point.y - segment.start.y) }
        let projection = min(max(
            ((point.x - segment.start.x) * dx + (point.y - segment.start.y) * dy) / lengthSquared,
            0
        ), 1)
        return hypot(
            point.x - (segment.start.x + projection * dx),
            point.y - (segment.start.y + projection * dy)
        )
    }
}
