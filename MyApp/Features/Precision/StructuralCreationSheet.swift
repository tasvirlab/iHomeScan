import SwiftUI

struct StructuralCreationSheet: View {
    @Binding var draft: StructuralCreationDraft
    let showsChooser: Bool
    let errorKey: String?
    let onBeginColumn: (ColumnShape) -> Void
    let onBeginBeam: () -> Void
    let onConfirm: () -> Void
    let onClose: () -> Void

    @Environment(AppSettings.self) private var settings
    @State private var selectedShape: ColumnShape = .rectangular
    @State private var showsOptional = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if showsChooser {
                        StructuralElementChooser(
                            selectedShape: $selectedShape,
                            onBeginColumn: onBeginColumn,
                            onBeginBeam: onBeginBeam
                        )
                    } else {
                        StructuralDimensionForm(
                            draft: $draft,
                            showsOptional: $showsOptional,
                            errorKey: errorKey,
                            onConfirm: onConfirm
                        )
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.surface)
            .navigationTitle(settings.t(showsChooser ? "precision.structural.addTitle" : dimensionTitleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(settings.t("common.close"))
                }
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize || showsOptional ? [.large] : [.height(showsChooser ? 330 : 430), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(draft.isSaving)
    }

    private var dimensionTitleKey: String {
        draft.kind == .beam ? "precision.structural.beamTitle" : "precision.structural.columnTitle"
    }
}

private struct StructuralElementChooser: View {
    @Binding var selectedShape: ColumnShape
    let onBeginColumn: (ColumnShape) -> Void
    let onBeginBeam: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 16) {
            Picker(settings.t("precision.structural.shape"), selection: $selectedShape) {
                Text(settings.t("precision.structural.rectangular")).tag(ColumnShape.rectangular)
                Text(settings.t("precision.structural.square")).tag(ColumnShape.square)
                Text(settings.t("precision.structural.circular")).tag(ColumnShape.circular)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("structural.shape.picker")

            Button {
                onBeginColumn(selectedShape)
            } label: {
                StructuralChoiceLabel(
                    title: settings.t("precision.structural.column"),
                    subtitle: settings.t("precision.structural.columnHint"),
                    systemImage: selectedShape == .circular ? "circle" : "square"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("structural.add.column")

            Button(action: onBeginBeam) {
                StructuralChoiceLabel(
                    title: settings.t("precision.structural.beam"),
                    subtitle: settings.t("precision.structural.beamHint"),
                    systemImage: "rectangle.dashed"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("structural.add.beam")
        }
    }
}

private struct StructuralChoiceLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 44, height: 44)
                .background(Palette.accent.opacity(0.1), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Palette.inkTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 68)
        .background(Palette.background, in: .rect(cornerRadius: Radius.medium))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(Palette.line, lineWidth: 0.5))
        .contentShape(.rect)
    }
}

private struct StructuralDimensionForm: View {
    @Binding var draft: StructuralCreationDraft
    @Binding var showsOptional: Bool
    let errorKey: String?
    let onConfirm: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 14) {
            if draft.kind == .column {
                if draft.columnShape == .rectangular {
                    StructuralMillimeterField(
                        title: settings.t("precision.structural.width"),
                        text: $draft.widthMillimeters,
                        identifier: "structural.width"
                    )
                    StructuralMillimeterField(
                        title: settings.t("precision.structural.depth"),
                        text: $draft.depthMillimeters,
                        identifier: "structural.depth"
                    )
                } else {
                    StructuralMillimeterField(
                        title: settings.t(draft.columnShape == .circular
                            ? "precision.structural.diameter" : "precision.structural.side"),
                        text: $draft.widthMillimeters,
                        identifier: "structural.width"
                    )
                }
            } else {
                StructuralMillimeterField(
                    title: settings.t("precision.structural.width"),
                    text: $draft.widthMillimeters,
                    identifier: "structural.width"
                )
                StructuralMillimeterField(
                    title: settings.t("precision.structural.depth"),
                    text: $draft.depthMillimeters,
                    identifier: "structural.depth"
                )
            }

            DisclosureGroup(isExpanded: $showsOptional) {
                VStack(spacing: 12) {
                    if draft.kind == .column {
                        StructuralMillimeterField(
                            title: settings.t("precision.structural.height"),
                            text: $draft.heightMillimeters,
                            identifier: "structural.height",
                            optional: true
                        )
                        StructuralNumberField(
                            title: settings.t("precision.structural.rotation"),
                            suffix: "°",
                            text: $draft.rotationDegrees,
                            identifier: "structural.rotation"
                        )
                        StructuralMillimeterField(
                            title: settings.t("precision.structural.baseElevation"),
                            text: $draft.baseElevationMillimeters,
                            identifier: "structural.baseElevation",
                            optional: true
                        )
                    } else {
                        StructuralMillimeterField(
                            title: settings.t("precision.structural.bottomElevation"),
                            text: $draft.bottomElevationMillimeters,
                            identifier: "structural.bottomElevation",
                            optional: true
                        )
                        StructuralMillimeterField(
                            title: settings.t("precision.structural.topElevation"),
                            text: $draft.topElevationMillimeters,
                            identifier: "structural.topElevation",
                            optional: true
                        )
                    }
                }
                .padding(.top, 12)
            } label: {
                Text(settings.t("precision.structural.optional"))
                    .font(Typography.control)
                    .foregroundStyle(Palette.ink)
            }

            if let errorKey {
                Label(settings.t(errorKey), systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("structural.error")
            }

            Button(action: onConfirm) {
                HStack {
                    if draft.isSaving { ProgressView().tint(Palette.onAccent) }
                    Text(settings.t(draft.kind == .beam
                        ? "precision.structural.addBeam" : "precision.structural.addColumn"))
                }
                .font(Typography.button)
                .foregroundStyle(Palette.onAccent)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Palette.accent, in: .rect(cornerRadius: Radius.medium))
            }
            .buttonStyle(.pressable)
            .disabled(draft.isSaving)
            .accessibilityIdentifier("structural.confirm")
        }
    }
}

private struct StructuralMillimeterField: View {
    let title: String
    @Binding var text: String
    let identifier: String
    var optional = false
    @Environment(AppSettings.self) private var settings

    var body: some View {
        StructuralNumberField(
            title: optional ? "\(title) · \(settings.t("precision.structural.optionalShort"))" : title,
            suffix: "mm",
            text: $text,
            identifier: identifier
        )
    }
}

private struct StructuralNumberField: View {
    let title: String
    let suffix: String
    @Binding var text: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.meta)
                .foregroundStyle(Palette.inkSecondary)
            HStack {
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityIdentifier(identifier)
                Text(suffix)
                    .font(Typography.control)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Palette.background, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
        }
    }
}
