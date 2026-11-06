import SwiftUI

/// Draws a `FloorPlan` with SwiftUI `Canvas`.
///
/// Geometry is stored in meters and converted to millimeters for drawing (the stroke widths and
/// offsets below are in millimeters). It is fitted into the view, then the user's zoom and pan are
/// applied around the view center. Text is drawn in screen space so it stays crisp at any zoom.
struct FloorPlanCanvas: View {
    enum Style {
        /// Room names only — used for previews.
        case plain
        /// Room names, areas and outer dimension lines — used in the project detail and PDF.
        case draft
        /// Walls only, no grid or text — used for small thumbnails.
        case thumbnail
    }

    /// Plan geometry in meters.
    let plan: FloorPlan
    var style: Style = .draft
    /// Room names and areas keyed by `FloorPlan.PlanRoom.id`, sourced from the database.
    var labels: [String: PlanRoomLabel] = [:]
    var selectedRoomID: String?
    var showsGrid = true
    var zoom: CGFloat = 1
    var offset: CGSize = .zero
    /// Space reserved for overlaid controls; the plan is fitted into the remaining area.
    var contentInsets = EdgeInsets()

    @Environment(AppSettings.self) private var settings

    private static let millimetersPerMeter: CGFloat = 1000

    /// Visible area around a millimeter plan, leaving room for dimension labels.
    private static func viewBox(forMillimeterPlan plan: FloorPlan, style: Style) -> CGRect {
        let margin: CGFloat = style == .thumbnail ? 300 : 1150
        return CGRect(x: plan.bounds.minX - margin, y: plan.bounds.minY - margin,
                      width: plan.bounds.width + margin * 2, height: plan.bounds.height + margin * 2 + 50)
    }

    /// Maps plan coordinates in **meters** to view coordinates.
    static func transform(
        for plan: FloorPlan, in size: CGSize, insets: EdgeInsets = EdgeInsets(),
        zoom: CGFloat, offset: CGSize, style: Style = .draft
    ) -> CGAffineTransform {
        millimeterTransform(for: plan.scaled(by: millimetersPerMeter), in: size, insets: insets,
                            zoom: zoom, offset: offset, style: style)
            .scaledBy(x: millimetersPerMeter, y: millimetersPerMeter)
    }

    /// Maps plan coordinates in millimeters to view coordinates.
    private static func millimeterTransform(
        for plan: FloorPlan, in size: CGSize, insets: EdgeInsets, zoom: CGFloat, offset: CGSize, style: Style
    ) -> CGAffineTransform {
        let box = viewBox(forMillimeterPlan: plan, style: style)
        let available = CGRect(
            x: insets.leading, y: insets.top,
            width: max(size.width - insets.leading - insets.trailing, 1),
            height: max(size.height - insets.top - insets.bottom, 1)
        )
        let fit = min(available.width / box.width, available.height / box.height)
        let scale = fit * zoom
        return CGAffineTransform.identity
            .translatedBy(x: available.midX + offset.width, y: available.midY + offset.height)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -box.midX, y: -box.midY)
    }

    var body: some View {
        let plan = plan.scaled(by: Self.millimetersPerMeter)
        Canvas { context, size in
            if showsGrid && style != .thumbnail {
                drawGrid(in: &context, size: size)
            }

            let transform = Self.millimeterTransform(for: plan, in: size, insets: contentInsets,
                                                     zoom: zoom, offset: offset, style: style)
            let scale = transform.a

            var planContext = context
            planContext.concatenate(transform)
            drawGeometry(plan, in: &planContext)

            if style != .thumbnail {
                drawLabels(plan, in: &context, transform: transform, scale: scale)
            }
        }
        .background(Palette.planBackground)
    }

    // MARK: - Drawing

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 18
        var grid = Path()
        var x: CGFloat = 0
        while x <= size.width {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= size.height {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        context.stroke(grid, with: .color(Palette.planGrid), lineWidth: 1)
    }

    private func drawGeometry(_ plan: FloorPlan, in context: inout GraphicsContext) {
        // Floor
        context.fill(Path(plan.bounds), with: .color(Palette.planFloor))

        // Selected room highlight
        if let room = plan.rooms.first(where: { $0.id == selectedRoomID }) {
            let rect = Path(roundedRect: room.rect.insetBy(dx: 110, dy: 110), cornerRadius: 140)
            context.fill(rect, with: .color(Palette.accent.opacity(0.1)))
            context.stroke(rect, with: .color(Palette.accent), lineWidth: 36)
        }

        // Walls
        var outer = Path()
        for polyline in plan.outerWalls { outer.addLines(polyline) }
        context.stroke(outer, with: .color(Palette.wall),
                       style: StrokeStyle(lineWidth: 220, lineCap: .square, lineJoin: .miter))

        var inner = Path()
        for wall in plan.innerWalls {
            inner.move(to: wall.start)
            inner.addLine(to: wall.end)
        }
        context.stroke(inner, with: .color(Palette.wall), style: StrokeStyle(lineWidth: 130, lineCap: .square))

        // Real RoomPlan openings are preserved as rotated projected segments in metadata.
        // Cut them out of the wall before drawing door leaves and window center lines.
        drawRoomPlanOpenings(plan, in: &context)

        // Door leaves and swing arcs
        var doors = Path()
        for door in plan.doors {
            let start = Angle(degrees: door.startAngle)
            doors.move(to: door.hinge)
            doors.addLine(to: CGPoint(x: door.hinge.x + door.radius * cos(start.radians),
                                      y: door.hinge.y + door.radius * sin(start.radians)))
            // In a y-down coordinate space, increasing angles sweep visually clockwise,
            // which SwiftUI expresses as `clockwise: false`.
            doors.addArc(center: door.hinge, radius: door.radius, startAngle: start,
                         endAngle: .degrees(door.endAngle), clockwise: door.endAngle < door.startAngle)
        }
        context.stroke(doors, with: .color(Palette.inkTertiary), lineWidth: 22)

        // Legacy/sample windows. Real RoomPlan windows use their rotated metadata segments below.
        if plan.roomPlanMetadata == nil {
            for window in plan.windows {
            context.fill(Path(window), with: .color(Palette.planFloor))
            context.stroke(Path(window), with: .color(Palette.wall), lineWidth: 26)
            var center = Path()
            if window.width > window.height {
                center.move(to: CGPoint(x: window.minX, y: window.midY))
                center.addLine(to: CGPoint(x: window.maxX, y: window.midY))
            } else {
                center.move(to: CGPoint(x: window.midX, y: window.minY))
                center.addLine(to: CGPoint(x: window.midX, y: window.maxY))
            }
            context.stroke(center, with: .color(Palette.wall), lineWidth: 22)
            }
        }

        if style == .draft {
            drawDimensionLines(plan, in: &context)
        }
    }

    private func drawRoomPlanOpenings(_ plan: FloorPlan, in context: inout GraphicsContext) {
        guard let metadata = plan.roomPlanMetadata else { return }
        for surface in metadata.surfaces {
            guard [.door, .window, .opening].contains(surface.kind),
                  let segment = surface.projectedSegment else { continue }
            let start = CGPoint(x: segment.start.x * Self.millimetersPerMeter,
                                y: segment.start.y * Self.millimetersPerMeter)
            let end = CGPoint(x: segment.end.x * Self.millimetersPerMeter,
                              y: segment.end.y * Self.millimetersPerMeter)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(Palette.planFloor),
                           style: StrokeStyle(lineWidth: 245, lineCap: .butt))
            if surface.kind == .window {
                context.stroke(path, with: .color(Palette.accentText),
                               style: StrokeStyle(lineWidth: 34, lineCap: .butt))
            } else if surface.kind == .opening {
                context.stroke(path, with: .color(Palette.inkTertiary.opacity(0.45)),
                               style: StrokeStyle(lineWidth: 14, lineCap: .butt, dash: [70, 55]))
            }
        }
    }

    private func drawDimensionLines(_ plan: FloorPlan, in context: inout GraphicsContext) {
        var lines = Path()
        var ticks = Path()
        for dimension in plan.dimensions {
            lines.move(to: dimension.start)
            lines.addLine(to: dimension.end)

            // Extension lines perpendicular to the dimension, reaching toward the wall.
            let isHorizontal = dimension.start.y == dimension.end.y
            for point in [dimension.start, dimension.end] {
                let toward = extensionRange(for: point, horizontal: isHorizontal, bounds: plan.bounds)
                if isHorizontal {
                    lines.move(to: CGPoint(x: point.x, y: toward.lowerBound))
                    lines.addLine(to: CGPoint(x: point.x, y: toward.upperBound))
                } else {
                    lines.move(to: CGPoint(x: toward.lowerBound, y: point.y))
                    lines.addLine(to: CGPoint(x: toward.upperBound, y: point.y))
                }
                ticks.move(to: CGPoint(x: point.x - 90, y: point.y + 90))
                ticks.addLine(to: CGPoint(x: point.x + 90, y: point.y - 90))
            }
        }
        context.stroke(lines, with: .color(Palette.inkSecondary), lineWidth: 16)
        context.stroke(ticks, with: .color(Palette.inkSecondary), lineWidth: 40)
    }

    /// Extension line extent for a dimension point: from 150 mm beyond the line to 500 mm toward the plan.
    private func extensionRange(for point: CGPoint, horizontal: Bool, bounds: CGRect) -> ClosedRange<CGFloat> {
        if horizontal {
            let towardPlan: CGFloat = point.y < bounds.midY ? 500 : -500
            return ordered(point.y - towardPlan * 0.3, point.y + towardPlan)
        } else {
            let towardPlan: CGFloat = point.x < bounds.midX ? 500 : -500
            return ordered(point.x - towardPlan * 0.3, point.x + towardPlan)
        }
    }

    private func ordered(_ a: CGFloat, _ b: CGFloat) -> ClosedRange<CGFloat> { min(a, b)...max(a, b) }

    private func drawLabels(_ plan: FloorPlan, in context: inout GraphicsContext, transform: CGAffineTransform, scale: CGFloat) {
        // Font sizes are specified in plan millimeters, converted to points.
        let nameSize = 290 * scale
        let detailSize = 220 * scale

        for room in plan.rooms {
            guard let label = labels[room.id] else { continue }
            let isSelected = room.id == selectedRoomID
            let baseline = CGPoint(x: room.labelCenter.x, y: room.labelCenter.y + 100).applying(transform)
            context.draw(
                Text(label.name)
                    .font(.system(size: nameSize, weight: .semibold))
                    .foregroundStyle(Palette.ink),
                at: baseline, anchor: .bottom
            )
            if style == .draft, let area = label.area {
                let areaPoint = CGPoint(x: room.labelCenter.x, y: room.labelCenter.y + 460).applying(transform)
                context.draw(
                    Text(settings.area(area))
                        .font(.system(size: detailSize, weight: isSelected ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? Palette.accentText : Palette.inkSecondary),
                    at: areaPoint, anchor: .bottom
                )
            }
        }

        guard style == .draft else { return }
        for dimension in plan.dimensions {
            let point = dimension.labelPosition.applying(transform)
            var layer = context
            layer.translateBy(x: point.x, y: point.y)
            layer.rotate(by: .degrees(dimension.labelRotation))
            layer.draw(
                Text(settings.lengthValue(dimension.value))
                    .font(.system(size: detailSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.inkSecondary),
                at: .zero, anchor: .bottom
            )
        }
    }
}
