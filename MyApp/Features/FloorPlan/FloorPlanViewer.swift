import SwiftUI

/// Interactive floor plan: drag to pan, pinch or use the buttons to zoom, tap a room to select it.
struct FloorPlanViewer: View {
    /// Plan geometry in meters.
    let plan: FloorPlan
    var labels: [String: PlanRoomLabel] = [:]
    @Binding var selectedRoomID: String?
    var precisionPlan: ParametricFloorPlan?
    @Binding var selectedPrecisionWallID: UUID?
    @Binding var selectedPrecisionOpeningID: UUID?
    @Binding var selectedPrecisionColumnID: UUID?
    @Binding var selectedPrecisionBeamID: UUID?
    var onPrecisionWallSelected: ((UUID) -> Void)?
    var onPrecisionOpeningSelected: ((UUID) -> Void)?
    var onPrecisionColumnSelected: ((UUID) -> Void)?
    var onPrecisionBeamSelected: ((UUID) -> Void)?
    var onAddStructuralElement: (() -> Void)?
    var structuralPlacementActive = false
    var onStructuralPointSelected: ((PlanPoint2D) -> Void)?
    var onCancelStructuralPlacement: (() -> Void)?
    var structuralDraftPreview: StructuralCreationDraft?

    init(
        plan: FloorPlan,
        labels: [String: PlanRoomLabel] = [:],
        selectedRoomID: Binding<String?>,
        precisionPlan: ParametricFloorPlan? = nil,
        selectedPrecisionWallID: Binding<UUID?> = .constant(nil),
        selectedPrecisionOpeningID: Binding<UUID?> = .constant(nil),
        selectedPrecisionColumnID: Binding<UUID?> = .constant(nil),
        selectedPrecisionBeamID: Binding<UUID?> = .constant(nil),
        onPrecisionWallSelected: ((UUID) -> Void)? = nil,
        onPrecisionOpeningSelected: ((UUID) -> Void)? = nil,
        onPrecisionColumnSelected: ((UUID) -> Void)? = nil,
        onPrecisionBeamSelected: ((UUID) -> Void)? = nil,
        onAddStructuralElement: (() -> Void)? = nil,
        structuralPlacementActive: Bool = false,
        onStructuralPointSelected: ((PlanPoint2D) -> Void)? = nil,
        onCancelStructuralPlacement: (() -> Void)? = nil,
        structuralDraftPreview: StructuralCreationDraft? = nil
    ) {
        self.plan = plan
        self.labels = labels
        _selectedRoomID = selectedRoomID
        self.precisionPlan = precisionPlan
        _selectedPrecisionWallID = selectedPrecisionWallID
        _selectedPrecisionOpeningID = selectedPrecisionOpeningID
        _selectedPrecisionColumnID = selectedPrecisionColumnID
        _selectedPrecisionBeamID = selectedPrecisionBeamID
        self.onPrecisionWallSelected = onPrecisionWallSelected
        self.onPrecisionOpeningSelected = onPrecisionOpeningSelected
        self.onPrecisionColumnSelected = onPrecisionColumnSelected
        self.onPrecisionBeamSelected = onPrecisionBeamSelected
        self.onAddStructuralElement = onAddStructuralElement
        self.structuralPlacementActive = structuralPlacementActive
        self.onStructuralPointSelected = onStructuralPointSelected
        self.onCancelStructuralPlacement = onCancelStructuralPlacement
        self.structuralDraftPreview = structuralDraftPreview
    }

    @Environment(AppSettings.self) private var settings

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private let zoomRange: ClosedRange<CGFloat> = 0.6...3
    /// Keeps the fitted plan clear of the zoom controls on the trailing edge.
    private let planInsets = EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 52)

    private var effectiveZoom: CGFloat { clampedZoom(zoom * pinch) }
    private var effectiveOffset: CGSize {
        CGSize(width: offset.width + drag.width, height: offset.height + drag.height)
    }
    private var alignmentRotation: CGFloat {
        if let precisionPlan {
            return FloorPlanAlignmentEngine.alignment(for: precisionPlan).rotation
        }
        return FloorPlanAlignmentEngine.alignment(for: plan).rotation
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                FloorPlanCanvas(
                    plan: plan,
                    style: .draft,
                    labels: labels,
                    selectedRoomID: selectedRoomID,
                    zoom: effectiveZoom,
                    offset: effectiveOffset,
                    rotation: alignmentRotation,
                    precisionPlan: precisionPlan,
                    selectedPrecisionWallID: selectedPrecisionWallID,
                    selectedPrecisionOpeningID: selectedPrecisionOpeningID,
                    selectedPrecisionColumnID: selectedPrecisionColumnID,
                    selectedPrecisionBeamID: selectedPrecisionBeamID,
                    contentInsets: planInsets
                )
                .contentShape(.rect)
                .highPriorityGesture(
                    SpatialTapGesture(coordinateSpace: .local)
                        .onEnded { selectRoom(at: $0.location, in: proxy.size) }
                )
                .simultaneousGesture(panGesture.simultaneously(with: zoomGesture))

                structuralPlacementPreview(in: proxy.size)
                openingAccessibilityTargets(in: proxy.size)
                structuralAccessibilityTargets(in: proxy.size)
            }
        }
        .overlay(alignment: .bottomLeading) { unitBadge }
        .overlay(alignment: .bottomTrailing) { zoomControls }
        .overlay(alignment: .topTrailing) { addStructuralButton }
        .overlay(alignment: .top) { structuralPlacementHint }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(settings.t("plan.accessibility"))
        .accessibilityIdentifier("precision.floorPlanCanvas")
    }

    @ViewBuilder
    private func structuralPlacementPreview(in size: CGSize) -> some View {
        if let draft = structuralDraftPreview,
           draft.columnPosition != nil || draft.beamStart != nil {
            let transform = FloorPlanCanvas.transform(
                for: plan, in: size, insets: planInsets,
                zoom: effectiveZoom, offset: effectiveOffset,
                rotation: alignmentRotation, precisionPlan: precisionPlan
            )
            Canvas { context, _ in
                var path = Path()
                if let position = draft.columnPosition {
                    let center = CGPoint(x: position.x, y: position.y).applying(transform)
                    let width = previewMeters(draft.widthMillimeters)
                    let depth = draft.columnShape == .rectangular
                        ? previewMeters(draft.depthMillimeters) : width
                    if let width, let depth {
                        let angle = (Double(draft.rotationDegrees) ?? 0) * .pi / 180
                        let corners = [
                            PlanPoint2D(x: -width / 2, y: -depth / 2),
                            PlanPoint2D(x: width / 2, y: -depth / 2),
                            PlanPoint2D(x: width / 2, y: depth / 2),
                            PlanPoint2D(x: -width / 2, y: depth / 2)
                        ].map { point -> CGPoint in
                            let rotated = PlanPoint2D(
                                x: position.x + point.x * cos(angle) - point.y * sin(angle),
                                y: position.y + point.x * sin(angle) + point.y * cos(angle)
                            )
                            return CGPoint(x: rotated.x, y: rotated.y).applying(transform)
                        }
                        if draft.columnShape == .circular {
                            let edge = CGPoint(x: position.x + width / 2, y: position.y).applying(transform)
                            let radius = hypot(edge.x - center.x, edge.y - center.y)
                            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                                       width: radius * 2, height: radius * 2))
                        } else if let first = corners.first {
                            path.move(to: first)
                            corners.dropFirst().forEach { path.addLine(to: $0) }
                            path.closeSubpath()
                        }
                    } else {
                        path.addEllipse(in: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20))
                    }
                    context.fill(path, with: .color(Palette.accent.opacity(0.18)))
                    context.stroke(path, with: .color(Palette.accent), style: .init(lineWidth: 2, dash: [5, 3]))
                } else if let start = draft.beamStart {
                    let a = CGPoint(x: start.x, y: start.y).applying(transform)
                    if let end = draft.beamEnd {
                        let b = CGPoint(x: end.x, y: end.y).applying(transform)
                        path.move(to: a)
                        path.addLine(to: b)
                    } else {
                        path.addEllipse(in: CGRect(x: a.x - 7, y: a.y - 7, width: 14, height: 14))
                    }
                    context.stroke(path, with: .color(Palette.accent), style: .init(lineWidth: 4, dash: [8, 5]))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func previewMeters(_ millimeters: String) -> Double? {
        guard let value = Double(millimeters.replacingOccurrences(of: ",", with: ".")),
              value.isFinite, value > 0 else { return nil }
        return value / 1_000
    }

    @ViewBuilder
    private func structuralAccessibilityTargets(in size: CGSize) -> some View {
        if let precisionPlan {
            let transform = FloorPlanCanvas.transform(
                for: plan, in: size, insets: planInsets,
                zoom: effectiveZoom, offset: effectiveOffset,
                rotation: alignmentRotation, precisionPlan: precisionPlan
            )
            let targets = StructuralHitTesting.targets(for: precisionPlan, transform: transform)
            ForEach(targets, id: \.id) { target in
                Button {
                    selectedPrecisionWallID = nil
                    selectedPrecisionOpeningID = nil
                    if target.kind == .column {
                        selectedPrecisionColumnID = target.id
                        selectedPrecisionBeamID = nil
                        onPrecisionColumnSelected?(target.id)
                    } else {
                        selectedPrecisionColumnID = nil
                        selectedPrecisionBeamID = target.id
                        onPrecisionBeamSelected?(target.id)
                    }
                } label: {
                    Color.clear
                        .frame(width: max(target.bounds.width, 44), height: max(target.bounds.height, 44))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .position(x: target.bounds.midX, y: target.bounds.midY)
                .accessibilityLabel(settings.t(target.kind == .column
                                                ? "precision.structural.column"
                                                : "precision.structural.beam"))
                .accessibilityIdentifier("precision.\(target.kind == .column ? "column" : "beam").\(target.id.uuidString)")
            }
        }
    }

    @ViewBuilder
    private func openingAccessibilityTargets(in size: CGSize) -> some View {
        if let precisionPlan {
            let transform = FloorPlanCanvas.transform(
                for: plan, in: size, insets: planInsets,
                zoom: effectiveZoom, offset: effectiveOffset,
                rotation: alignmentRotation, precisionPlan: precisionPlan
            )
            let targets = PrecisionOpeningHitTesting.targets(for: precisionPlan, transform: transform)
            ForEach(Array(targets.enumerated()), id: \.element.openingID) { index, target in
                let midpoint = CGPoint(
                    x: (target.start.x + target.end.x) / 2,
                    y: (target.start.y + target.end.y) / 2
                )
                let width = max(hypot(target.end.x - target.start.x, target.end.y - target.start.y), 44)
                Button {
                    selectedPrecisionWallID = nil
                    selectedPrecisionOpeningID = target.openingID
                    onPrecisionOpeningSelected?(target.openingID)
                } label: {
                    Color.clear
                        .frame(width: width, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .rotationEffect(.radians(atan2(target.end.y - target.start.y, target.end.x - target.start.x)))
                .position(midpoint)
                .accessibilityLabel(openingAccessibilityLabel(id: target.openingID, index: index))
                .accessibilityIdentifier("precision.opening.\(target.openingID.uuidString)")
            }
        }
    }

    private func openingAccessibilityLabel(id: UUID, index: Int) -> String {
        guard let opening = precisionPlan?.openings.first(where: { $0.id == id }) else {
            return settings.t("precision.opening.genericTitle", String(index + 1))
        }
        switch opening.kind {
        case .door: return settings.t("precision.opening.doorTitle", String(index + 1))
        case .window: return settings.t("precision.opening.windowTitle", String(index + 1))
        case .opening: return settings.t("precision.opening.genericTitle", String(index + 1))
        }
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in zoom = clampedZoom(zoom * value.magnification) }
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, zoomRange.lowerBound), zoomRange.upperBound)
    }

    private func selectRoom(at location: CGPoint, in size: CGSize) {
        let transform = FloorPlanCanvas.transform(for: plan, in: size, insets: planInsets,
                                                  zoom: effectiveZoom, offset: effectiveOffset,
                                                  rotation: alignmentRotation, precisionPlan: precisionPlan)
        if structuralPlacementActive {
            let point = location.applying(transform.inverted())
            guard point.x.isFinite, point.y.isFinite else { return }
            onStructuralPointSelected?(.init(x: point.x, y: point.y))
            return
        }
        if let openingID = precisionOpening(at: location, transform: transform) {
            selectedPrecisionWallID = nil
            selectedPrecisionOpeningID = openingID
            onPrecisionOpeningSelected?(openingID)
            return
        }
        if let target = structuralElement(at: location, transform: transform) {
            selectedPrecisionWallID = nil
            selectedPrecisionOpeningID = nil
            switch target.kind {
            case .column:
                selectedPrecisionColumnID = target.id
                selectedPrecisionBeamID = nil
                onPrecisionColumnSelected?(target.id)
            case .beam:
                selectedPrecisionBeamID = target.id
                selectedPrecisionColumnID = nil
                onPrecisionBeamSelected?(target.id)
            }
            return
        }
        if let wallID = precisionWall(at: location, transform: transform, size: size) {
            selectedPrecisionOpeningID = nil
            selectedPrecisionWallID = wallID
            onPrecisionWallSelected?(wallID)
            return
        }
        let point = location.applying(transform.inverted())
        let room = plan.rooms.first { $0.rect.contains(point) }
        withAnimation(.easeOut(duration: 0.2)) {
            selectedRoomID = room?.id == selectedRoomID ? nil : room?.id
        }
    }

    private func structuralElement(at location: CGPoint, transform: CGAffineTransform) -> StructuralHitTarget? {
        guard let precisionPlan else { return nil }
        return StructuralHitTesting.selected(
            at: location,
            targets: StructuralHitTesting.targets(for: precisionPlan, transform: transform)
        )
    }

    private func precisionOpening(at location: CGPoint, transform: CGAffineTransform) -> UUID? {
        guard let precisionPlan else { return nil }
        let targets = PrecisionOpeningHitTesting.targets(
            for: precisionPlan,
            transform: transform,
            selectedOpeningID: selectedPrecisionOpeningID
        )
        return PrecisionOpeningHitTesting.selectedOpening(at: location, targets: targets)
    }

    private func precisionWall(at location: CGPoint, transform: CGAffineTransform, size: CGSize) -> UUID? {
        guard let precisionPlan else { return nil }
        let dimensions = FloorPlanCanvas.precisionDimensions(precisionPlan)
        let annotations = FloorPlanDimensionLayoutEngine.layout(
            dimensions: dimensions, transform: transform,
            canvasBounds: CGRect(origin: .zero, size: size),
            planCenter: CGPoint(x: plan.bounds.midX, y: plan.bounds.midY),
            textForValue: settings.lengthValue,
            avoiding: FloorPlanCanvas.dimensionAvoidanceRects(
                plan: plan, precisionPlan: precisionPlan, labels: labels, transform: transform
            )
        )
        if let annotation = annotations.first(where: { $0.labelBounds.insetBy(dx: -8, dy: -8).contains(location) }),
           annotation.sourceIndex < precisionPlan.walls.count {
            return precisionPlan.walls[annotation.sourceIndex].id
        }
        let vertices = Dictionary(uniqueKeysWithValues: precisionPlan.vertices.map { ($0.id, $0.position) })
        let targets = precisionPlan.walls.compactMap { wall -> PrecisionWallHitTarget? in
            guard let start = vertices[wall.startVertexID], let end = vertices[wall.endVertexID] else { return nil }
            return PrecisionWallHitTarget(
                wallID: wall.id,
                start: CGPoint(x: start.x, y: start.y).applying(transform),
                end: CGPoint(x: end.x, y: end.y).applying(transform)
            )
        }
        return PrecisionWallHitTesting.selectedWall(at: location, targets: targets)
    }

    private func setZoom(_ value: CGFloat) {
        withAnimation(.snappy) { zoom = clampedZoom(value) }
    }

    // MARK: - Overlays

    private var unitBadge: some View {
        Text(settings.t(settings.units == .millimeters ? "plan.units.mm" : "plan.units.m"))
            .font(.caption.monospaced().weight(.medium))
            .foregroundStyle(Palette.inkSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))
            .padding(12)
    }

    private var zoomControls: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                controlButton("plus", labelKey: "plan.zoomIn") { setZoom(zoom * 1.25) }
                Rectangle().fill(Palette.line).frame(width: 22, height: 0.5)
                controlButton("minus", labelKey: "plan.zoomOut") { setZoom(zoom / 1.25) }
            }
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))

            controlButton("arrow.down.left.and.arrow.up.right", labelKey: "plan.reset") {
                withAnimation(.snappy) {
                    zoom = 1
                    offset = .zero
                }
            }
            .background(.ultraThinMaterial, in: .circle)
            .overlay(Circle().strokeBorder(Palette.line, lineWidth: 0.5))
        }
        .padding(12)
    }

    @ViewBuilder
    private var addStructuralButton: some View {
        if let onAddStructuralElement, !structuralPlacementActive {
            Button(action: onAddStructuralElement) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.accentText)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: .circle)
                    .overlay(Circle().strokeBorder(Palette.accent.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel(settings.t("precision.structural.addTitle"))
            .accessibilityIdentifier("structural.add.button")
        }
    }

    @ViewBuilder
    private var structuralPlacementHint: some View {
        if structuralPlacementActive {
            HStack(spacing: 8) {
                Label(settings.t(structuralPlacementHintKey), systemImage: "hand.tap")
                    .font(Typography.control)
                    .foregroundStyle(Palette.ink)
                    .accessibilityIdentifier("structural.placement.hint")
                if let onCancelStructuralPlacement {
                    Button(action: onCancelStructuralPlacement) {
                        Image(systemName: "xmark")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(settings.t("common.cancel"))
                    .accessibilityIdentifier("structural.placement.cancel")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(minHeight: 44)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))
            .padding(12)
        }
    }

    private var structuralPlacementHintKey: String {
        switch structuralDraftPreview?.placementStep {
        case .columnPoint: "precision.structural.tapColumnPlacement"
        case .beamStart: "precision.structural.tapBeamStart"
        case .beamEnd: "precision.structural.tapBeamEnd"
        default: "precision.structural.tapPlacement"
        }
    }

    private func controlButton(_ systemImage: String, labelKey: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settings.t(labelKey))
    }
}
