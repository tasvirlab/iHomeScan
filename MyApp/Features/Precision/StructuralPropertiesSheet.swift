import SwiftUI

struct StructuralPropertiesSheet: View {
    @Binding var draft: StructuralPropertiesDraft
    let canSave: Bool
    let errorKey: String?
    let onConfirm: () -> Void
    let onClose: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsPosition = false
    @State private var showsVertical = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StructuralPrimaryProperties(draft: $draft)
                    StructuralExpandableProperties(
                        draft: $draft,
                        showsPosition: $showsPosition,
                        showsVertical: $showsVertical
                    )
                    Toggle(settings.t("precision.structural.laserMeasured"), isOn: $draft.laserVerified)
                        .tint(Palette.accent)
                        .accessibilityIdentifier("structural.properties.laser")
                    if let errorKey {
                        Label(settings.t(errorKey), systemImage: "exclamationmark.triangle.fill")
                            .font(Typography.meta)
                            .foregroundStyle(Palette.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("structural.properties.error")
                    }
                    Button(action: onConfirm) {
                        HStack(spacing: 8) {
                            if draft.isSaving { ProgressView().tint(Palette.onAccent) }
                            Text(settings.t("precision.structural.confirmChanges"))
                        }
                        .font(Typography.button)
                        .foregroundStyle(Palette.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(canSave ? Palette.accent : Palette.inkTertiary, in: .rect(cornerRadius: Radius.medium))
                    }
                    .buttonStyle(.pressable)
                    .disabled(!canSave || draft.isSaving)
                    .accessibilityIdentifier("structural.properties.confirm")
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.surface)
            .navigationTitle(settings.t(draft.kind == .column
                ? "precision.structural.columnProperties" : "precision.structural.beamProperties"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .accessibilityLabel(settings.t("common.close"))
                        .accessibilityIdentifier("structural.properties.close")
                }
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize || showsPosition || showsVertical
            ? [.large] : [.height(470), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(draft.isSaving)
    }
}

private struct StructuralPrimaryProperties: View {
    @Binding var draft: StructuralPropertiesDraft
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 12) {
            if draft.kind == .column, draft.shape != .rectangular {
                StructuralPropertyField(
                    title: settings.t(draft.shape == .circular
                        ? "precision.structural.diameter" : "precision.structural.side"),
                    text: $draft.widthMillimeters,
                    identifier: "structural.properties.width"
                )
            } else {
                StructuralPropertyField(
                    title: settings.t("precision.structural.width"),
                    text: $draft.widthMillimeters,
                    identifier: "structural.properties.width"
                )
                StructuralPropertyField(
                    title: settings.t("precision.structural.depth"),
                    text: $draft.depthMillimeters,
                    identifier: "structural.properties.depth"
                )
            }
            if draft.kind == .column {
                StructuralPropertyField(
                    title: settings.t("precision.structural.rotation"), suffix: "°",
                    text: $draft.rotationDegrees,
                    identifier: "structural.properties.rotation"
                )
            }
        }
    }
}

private struct StructuralExpandableProperties: View {
    @Binding var draft: StructuralPropertiesDraft
    @Binding var showsPosition: Bool
    @Binding var showsVertical: Bool
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 12) {
            DisclosureGroup(isExpanded: $showsPosition) {
                VStack(spacing: 12) {
                    if draft.kind == .column {
                        StructuralPropertyField(title: settings.t("precision.structural.positionX"), text: $draft.positionXMillimeters,
                                                identifier: "structural.properties.positionX")
                        StructuralPropertyField(title: settings.t("precision.structural.positionY"), text: $draft.positionYMillimeters,
                                                identifier: "structural.properties.positionY")
                    } else {
                        StructuralPropertyCoordinatePair(
                            title: settings.t("precision.structural.startPoint"),
                            x: $draft.startXMillimeters, y: $draft.startYMillimeters,
                            identifier: "structural.properties.start"
                        )
                        StructuralPropertyCoordinatePair(
                            title: settings.t("precision.structural.endPoint"),
                            x: $draft.endXMillimeters, y: $draft.endYMillimeters,
                            identifier: "structural.properties.end"
                        )
                    }
                }
                .padding(.top, 12)
            } label: {
                Label(settings.t("precision.structural.position"), systemImage: "move.3d")
                    .font(Typography.control)
                    .foregroundStyle(Palette.ink)
            }

            DisclosureGroup(isExpanded: $showsVertical) {
                VStack(spacing: 12) {
                    if draft.kind == .column {
                        StructuralPropertyField(title: settings.t("precision.structural.height"), text: $draft.heightMillimeters,
                                                identifier: "structural.properties.height", optional: true)
                        StructuralPropertyField(title: settings.t("precision.structural.baseElevation"), text: $draft.baseElevationMillimeters,
                                                identifier: "structural.properties.baseElevation", optional: true)
                    } else {
                        StructuralPropertyField(title: settings.t("precision.structural.bottomElevation"), text: $draft.bottomElevationMillimeters,
                                                identifier: "structural.properties.bottomElevation", optional: true)
                        StructuralPropertyField(title: settings.t("precision.structural.topElevation"), text: $draft.topElevationMillimeters,
                                                identifier: "structural.properties.topElevation", optional: true)
                    }
                }
                .padding(.top, 12)
            } label: {
                Label(settings.t("precision.structural.verticalMeasurements"), systemImage: "arrow.up.and.down")
                    .font(Typography.control)
                    .foregroundStyle(Palette.ink)
            }
        }
    }
}

private struct StructuralPropertyCoordinatePair: View {
    let title: String
    @Binding var x: String
    @Binding var y: String
    let identifier: String
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Typography.meta).foregroundStyle(Palette.inkSecondary)
            HStack(spacing: 10) {
                StructuralPropertyField(title: settings.t("precision.structural.axisX"), text: $x,
                                        identifier: "\(identifier)X")
                StructuralPropertyField(title: settings.t("precision.structural.axisY"), text: $y,
                                        identifier: "\(identifier)Y")
            }
        }
    }
}

private struct StructuralPropertyField: View {
    let title: String
    var suffix = "mm"
    @Binding var text: String
    let identifier: String
    var optional = false
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(optional ? "\(title) · \(settings.t("precision.structural.optionalShort"))" : title)
                .font(Typography.meta)
                .foregroundStyle(Palette.inkSecondary)
            HStack {
                TextField("0", text: $text)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityIdentifier(identifier)
                Text(suffix).font(Typography.control).foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Palette.background, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
        }
    }
}
