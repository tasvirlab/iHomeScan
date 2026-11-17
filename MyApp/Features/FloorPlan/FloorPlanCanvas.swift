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
    /// Presentation-only auto-alignment in radians. Persisted coordinates remain unchanged.
    var rotation: CGFloat = 0
    /// Latest parametric geometry. When present, it is the authoritative editable wall layer.
    var precisionPlan: ParametricFloorPlan?
    var selectedPrecisionWallID: UUID?
    var selectedPrecisionOpeningID: UUID?
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
        zoom: CGFloat, offset: CGSize, rotation: CGFloat = 0, style: Style = .draft
    ) -> CGAffineTransform {
        millimeterTransform(for: plan.scaled(by: millimetersPerMeter), in: size, insets: insets,
                            zoom: zoom, offset: offset, rotation: rotation, style: style)
            .scaledBy(x: millimetersPerMeter, y: millimetersPerMeter)
    }

    /// Maps plan coordinates in millimeters to view coordinates.
    private static func millimeterTransform(
        for plan: FloorPlan, in size: CGSize, insets: EdgeInsets, zoom: CGFloat, offset: CGSize,
        rotation: CGFloat, style: Style
    ) -> CGAffineTransform {
        let box = viewBox(forMillimeterPlan: plan, style: style)
        let rotatedBox = rotatedBounds(of: box, by: rotation)
        let available = CGRect(
            x: insets.leading, y: insets.top,
            width: max(size.width - insets.leading - insets.trailing, 1),
            height: max(size.height - insets.top - insets.bottom, 1)
        )
        let fit = min(available.width / rotatedBox.width, available.height / rotatedBox.height)
        let scale = fit * zoom
        return CGAffineTransform.identity
            .translatedBy(x: available.midX + offset.width, y: available.midY + offset.height)
            .scaledBy(x: scale, y: scale)
            .rotated(by: rotation)
            .translatedBy(x: -box.midX, y: -box.midY)
    }

    private static func rotatedBounds(of rect: CGRect, by angle: CGFloat) -> CGRect {
        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .rotated(by: angle)
            .translatedBy(x: -rect.midX, y: -rect.midY)
        return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            .map { $0.applying(transform) }
            .reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    var body: some View {
        let plan = plan.scaled(by: Self.millimetersPerMeter)
        Canvas { context, size in
            if showsGrid && style != .thumbnail {
                drawGrid(in: &context, size: size)
            }

            let transform = Self.millimeterTransform(for: plan, in: size, insets: contentInsets,
                                                     zoom: zoom, offset: offset, rotation: rotation, style: style)
            let scale = hypot(transform.a, transform.c)

            var planContext = context
            planContext.concatenate(transform)
            drawGeometry(plan, precisionPlan: precisionPlan, in: &planContext)

            if style != .thumbnail {
                drawLabels(plan, precisionPlan: precisionPlan, in: &context, size: size, transform: transform, scale: scale)
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

    private func drawGeometry(_ plan: FloorPlan, precisionPlan: ParametricFloorPlan?, in context: inout GraphicsContext) {
        drawFloor(plan, precisionPlan: precisionPlan, in: &context)

        if let precisionPlan {
            drawPrecisionWalls(precisionPlan, in: &context)
        } else {
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
        }

        // Real RoomPlan openings are preserved as rotated projected segments in metadata.
        // Cut them out of the wall before drawing door leaves and window center lines.
        if let precisionPlan {
            drawPrecisionOpenings(precisionPlan, in: &context)
        } else {
            drawRoomPlanOpenings(plan, in: &context)
        }

        // Door leaves and swing arcs
        if precisionPlan == nil {
            var doors = Path()
            for door in plan.doors {
                let start = Angle(degrees: door.startAngle)
                doors.move(to: door.hinge)
                doors.addLine(to: CGPoint(x: door.hinge.x + door.radius * cos(start.radians),
                                          y: door.hinge.y + door.radius * sin(start.radians)))
                doors.addArc(center: door.hinge, radius: door.radius, startAngle: start,
                             endAngle: .degrees(door.endAngle), clockwise: door.endAngle < door.startAngle)
            }
            context.stroke(doors, with: .color(Palette.inkTertiary), lineWidth: 22)
        }

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

    }

    private func drawPrecisionWalls(_ precisionPlan: ParametricFloorPlan, in context: inout GraphicsContext) {
        let vertices = Dictionary(uniqueKeysWithValues: precisionPlan.vertices.map { ($0.id, $0.position) })
        for wall in precisionPlan.walls {
            guard let start = vertices[wall.startVertexID], let end = vertices[wall.endVertexID] else { continue }
            var path = Path()
            path.move(to: CGPoint(x: start.x * Self.millimetersPerMeter, y: start.y * Self.millimetersPerMeter))
            path.addLine(to: CGPoint(x: end.x * Self.millimetersPerMeter, y: end.y * Self.millimetersPerMeter))
            let selected = wall.id == selectedPrecisionWallID
            let thickness = CGFloat(wall.thickness?.value ?? 0.18) * Self.millimetersPerMeter
            context.stroke(path, with: .color(selected ? Palette.accent : Palette.wall),
                           style: StrokeStyle(lineWidth: max(thickness, selected ? 180 : 120), lineCap: .square, lineJoin: .miter))
        }
    }

    private func drawFloor(
        _ plan: FloorPlan,
        precisionPlan: ParametricFloorPlan?,
        in context: inout GraphicsContext
    ) {
        if let polygon = precisionPlan?.floorBoundary?.first, polygon.count >= 3 {
            var path = Path()
            path.addLines(polygon.map {
                CGPoint(x: $0.x * Self.millimetersPerMeter, y: $0.y * Self.millimetersPerMeter)
            })
            path.closeSubpath()
            context.fill(path, with: .color(Palette.planFloor.opacity(0.72)))
            return
        }
        if let metadata = plan.roomPlanMetadata {
            for surface in metadata.surfaces where surface.kind == .floor && surface.projectedPolygon.count >= 3 {
                var polygon = Path()
                polygon.addLines(surface.projectedPolygon.map {
                    CGPoint(x: $0.x * Self.millimetersPerMeter, y: $0.y * Self.millimetersPerMeter)
                })
                polygon.closeSubpath()
                context.fill(polygon, with: .color(Palette.planFloor.opacity(0.72)))
            }
        } else {
            // Legacy/sample plans intentionally use their rectangular authored bounds.
            context.fill(Path(plan.bounds), with: .color(Palette.planFloor))
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

    private func drawPrecisionOpenings(_ plan: ParametricFloorPlan, in context: inout GraphicsContext) {
        let vertices = Dictionary(uniqueKeysWithValues: plan.vertices.map { ($0.id, $0.position) })
        let walls = Dictionary(uniqueKeysWithValues: plan.walls.map { ($0.id, $0) })
        for opening in plan.openings {
            guard let wall = walls[opening.hostWallID], let start = vertices[wall.startVertexID],
                  let end = vertices[wall.endVertexID], let width = opening.width?.value else { continue }
            let wallLength = start.distance(to: end)
            guard wallLength > 0 else { continue }
            let anchorDistance: Double
            switch opening.horizontalAnchor {
            case .distanceFromStart(let measurement): anchorDistance = measurement.value
            }
            let lower = max(0, anchorDistance - width / 2)
            let upper = min(wallLength, anchorDistance + width / 2)
            guard upper > lower else { continue }
            let dx = (end.x - start.x) / wallLength
            let dy = (end.y - start.y) / wallLength
            let a = CGPoint(x: (start.x + dx * lower) * Self.millimetersPerMeter,
                            y: (start.y + dy * lower) * Self.millimetersPerMeter)
            let b = CGPoint(x: (start.x + dx * upper) * Self.millimetersPerMeter,
                            y: (start.y + dy * upper) * Self.millimetersPerMeter)
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            context.stroke(path, with: .color(Palette.planFloor), style: .init(lineWidth: 245, lineCap: .butt))
            let selected = opening.id == selectedPrecisionOpeningID
            let color = selected ? Palette.accent : (opening.kind == .window ? Palette.accentText : Palette.inkTertiary)
            context.stroke(path, with: .color(color), style: .init(lineWidth: opening.kind == .opening ? 14 : 28,
                                                                    lineCap: .butt,
                                                                    dash: opening.kind == .opening ? [70, 55] : []))
            if selected {
                let center = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 70, y: center.y - 70, width: 140, height: 140)),
                             with: .color(Palette.accent.opacity(0.18)))
                let referenceEndpoint = opening.architecturalMetadata?.measurements.first {
                    ($0.kind == .offsetFromStart || $0.kind == .offsetFromEnd)
                        && $0.reference?.reliability == .verified
                }?.reference?.endpoint
                if let referenceEndpoint {
                    let corner = referenceEndpoint == .wallStart
                        ? CGPoint(x: start.x * Self.millimetersPerMeter, y: start.y * Self.millimetersPerMeter)
                        : CGPoint(x: end.x * Self.millimetersPerMeter, y: end.y * Self.millimetersPerMeter)
                    context.fill(Path(ellipseIn: CGRect(x: corner.x - 65, y: corner.y - 65, width: 130, height: 130)),
                                 with: .color(Palette.accent.opacity(0.85)))
                }
            }
        }
    }

    private func drawDimensionLines(_ annotations: [FloorPlanDimensionLayoutEngine.Annotation],
                                    in context: inout GraphicsContext) {
        var lines = Path()
        var ticks = Path()
        for annotation in annotations {
            lines.move(to: annotation.lineStart)
            lines.addLine(to: annotation.lineEnd)
            lines.move(to: annotation.wallStart)
            lines.addLine(to: annotation.lineStart)
            lines.move(to: annotation.wallEnd)
            lines.addLine(to: annotation.lineEnd)
            let dx = annotation.lineEnd.x - annotation.lineStart.x
            let dy = annotation.lineEnd.y - annotation.lineStart.y
            let length = max(hypot(dx, dy), 1)
            let tangent = CGVector(dx: dx / length, dy: dy / length)
            for point in [annotation.lineStart, annotation.lineEnd] {
                ticks.move(to: CGPoint(x: point.x - tangent.dx * 4 - tangent.dy * 4,
                                       y: point.y - tangent.dy * 4 + tangent.dx * 4))
                ticks.addLine(to: CGPoint(x: point.x + tangent.dx * 4 + tangent.dy * 4,
                                          y: point.y + tangent.dy * 4 - tangent.dx * 4))
            }
        }
        context.stroke(lines, with: .color(Palette.inkSecondary.opacity(0.7)), lineWidth: 0.8)
        context.stroke(ticks, with: .color(Palette.inkSecondary.opacity(0.8)), lineWidth: 1.2)
    }

    private func drawLabels(_ plan: FloorPlan, precisionPlan: ParametricFloorPlan?, in context: inout GraphicsContext, size: CGSize,
                            transform: CGAffineTransform, scale: CGFloat) {
        // Font sizes are specified in plan millimeters, converted to points.
        let nameSize = 290 * scale
        let detailSize = 220 * scale

        for room in plan.rooms {
            guard let label = labels[room.id] else { continue }
            let isSelected = room.id == selectedRoomID
            let center = precisionLabelCenter(for: room, in: plan, precisionPlan: precisionPlan)
            let baseline = CGPoint(x: center.x, y: center.y - 70).applying(transform)
            context.draw(
                Text(label.name)
                    .font(.system(size: nameSize, weight: .semibold))
                    .foregroundStyle(Palette.ink),
                at: baseline, anchor: .bottom
            )
            if style == .draft, let area = label.area {
                let areaPoint = CGPoint(x: center.x, y: center.y + 270).applying(transform)
                context.draw(
                    Text(settings.area(area))
                        .font(.system(size: detailSize, weight: isSelected ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? Palette.accentText : Palette.inkSecondary),
                    at: areaPoint, anchor: .bottom
                )
            }
        }

        guard style == .draft else { return }
        let dimensions = precisionPlan.map { precisionPlan in
            Self.precisionDimensions(precisionPlan).map { dimension in
                FloorPlan.Dimension(
                    start: CGPoint(x: dimension.start.x * Self.millimetersPerMeter,
                                   y: dimension.start.y * Self.millimetersPerMeter),
                    end: CGPoint(x: dimension.end.x * Self.millimetersPerMeter,
                                 y: dimension.end.y * Self.millimetersPerMeter),
                    value: dimension.value,
                    labelPosition: CGPoint(x: dimension.labelPosition.x * Self.millimetersPerMeter,
                                           y: dimension.labelPosition.y * Self.millimetersPerMeter),
                    labelRotation: dimension.labelRotation
                )
            }
        } ?? plan.dimensions
        let annotations = FloorPlanDimensionLayoutEngine.layout(
            dimensions: dimensions, transform: transform,
            canvasBounds: CGRect(origin: .zero, size: size),
            planCenter: CGPoint(x: plan.bounds.midX, y: plan.bounds.midY),
            textForValue: settings.lengthValue
        )
        drawDimensionLines(annotations, in: &context)
        for annotation in annotations {
            context.fill(Path(roundedRect: annotation.labelBounds, cornerRadius: 5),
                         with: .color(Palette.planBackground.opacity(0.92)))
            let selected = precisionPlan.flatMap { plan in
                annotation.sourceIndex < plan.walls.count ? plan.walls[annotation.sourceIndex].id == selectedPrecisionWallID : false
            } ?? false
            context.draw(
                Text(settings.lengthValue(annotation.value))
                    .font(.system(size: max(detailSize, 11), weight: .medium, design: .monospaced))
                    .foregroundStyle(selected ? Palette.accentText : Palette.inkSecondary),
                at: annotation.labelCenter, anchor: .center
            )
        }
        drawSelectedOpeningDimensions(precisionPlan, in: &context, transform: transform, detailSize: detailSize)
    }

    private func drawSelectedOpeningDimensions(
        _ plan: ParametricFloorPlan?,
        in context: inout GraphicsContext,
        transform: CGAffineTransform,
        detailSize: CGFloat
    ) {
        guard let plan, let selectedPrecisionOpeningID,
              let opening = plan.openings.first(where: { $0.id == selectedPrecisionOpeningID }) else { return }
        let targets = PrecisionOpeningHitTesting.targets(for: plan, transform: transform, selectedOpeningID: selectedPrecisionOpeningID)
        guard let target = targets.first(where: { $0.openingID == selectedPrecisionOpeningID }),
              let bounds = target.labelBounds else { return }
        context.fill(Path(roundedRect: bounds, cornerRadius: 5), with: .color(Palette.planBackground.opacity(0.96)))
        context.draw(
            Text(settings.lengthValue(opening.width?.value ?? 0))
                .font(.system(size: max(detailSize, 11), weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.accentText),
            at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center
        )
    }

    private func precisionLabelCenter(
        for room: FloorPlan.PlanRoom,
        in plan: FloorPlan,
        precisionPlan: ParametricFloorPlan?
    ) -> CGPoint {
        guard let precisionPlan,
              plan.rooms.count == 1 || room.id == selectedRoomID else { return room.labelCenter }
        if let polygon = precisionPlan.floorBoundary?.first,
           let centroid = polygonCentroid(polygon) {
            return CGPoint(x: centroid.x * Self.millimetersPerMeter,
                           y: centroid.y * Self.millimetersPerMeter)
        }
        guard !precisionPlan.vertices.isEmpty else { return room.labelCenter }
        let count = Double(precisionPlan.vertices.count)
        return CGPoint(
            x: precisionPlan.vertices.reduce(0) { $0 + $1.position.x } / count * Self.millimetersPerMeter,
            y: precisionPlan.vertices.reduce(0) { $0 + $1.position.y } / count * Self.millimetersPerMeter
        )
    }

    private func polygonCentroid(_ polygon: [PlanPoint2D]) -> PlanPoint2D? {
        guard polygon.count >= 3 else { return nil }
        var doubledArea = 0.0
        var x = 0.0
        var y = 0.0
        for index in polygon.indices {
            let current = polygon[index]
            let next = polygon[(index + 1) % polygon.count]
            let cross = current.x * next.y - next.x * current.y
            doubledArea += cross
            x += (current.x + next.x) * cross
            y += (current.y + next.y) * cross
        }
        guard abs(doubledArea) > 0.000_001 else { return nil }
        return PlanPoint2D(x: x / (3 * doubledArea), y: y / (3 * doubledArea))
    }

    nonisolated static func precisionDimensions(_ plan: ParametricFloorPlan) -> [FloorPlan.Dimension] {
        let vertices = Dictionary(uniqueKeysWithValues: plan.vertices.map { ($0.id, $0.position) })
        return plan.walls.compactMap { wall in
            guard let start = vertices[wall.startVertexID], let end = vertices[wall.endVertexID] else { return nil }
            let a = CGPoint(x: start.x, y: start.y)
            let b = CGPoint(x: end.x, y: end.y)
            return FloorPlan.Dimension(start: a, end: b, value: hypot(b.x - a.x, b.y - a.y),
                                       labelPosition: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), labelRotation: 0)
        }
    }
}
