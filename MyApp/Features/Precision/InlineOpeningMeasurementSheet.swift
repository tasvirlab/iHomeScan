import SwiftUI

struct InlineOpeningMeasurementSheet: View {
    let openingKind: WallOpeningKind
    let ordinal: Int
    @Binding var draft: OpeningMeasurementDraft
    let preview: OpeningEditPreview?
    let isSaving: Bool
    let onConfirm: () -> Void
    let onClose: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsOtherMeasurements = false
    @State private var selectedDetent: PresentationDetent = .height(390)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                OpeningSheetHeader(title: title, onClose: onClose)
                if draft.referenceEndpoint == nil {
                    OpeningReferencePicker(selection: $draft.referenceEndpoint)
                }
                OpeningPrimaryFields(openingKind: openingKind, draft: $draft)
                DisclosureGroup(isExpanded: $showsOtherMeasurements) {
                    OpeningOptionalFields(openingKind: openingKind, draft: $draft)
                        .padding(.top, 12)
                } label: {
                    Text(settings.t("precision.opening.other"))
                        .font(Typography.control)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                if let preview, !preview.isValid {
                    Label(conflictText(preview), systemImage: "exclamationmark.triangle.fill")
                        .font(Typography.meta)
                        .foregroundStyle(Palette.error)
                        .accessibilityIdentifier("precision.opening.conflict")
                } else if draft.requiresReferenceForChanges {
                    Label(settings.t("precision.opening.referenceRequired"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(Typography.meta)
                        .foregroundStyle(Palette.accentText)
                } else if !draft.hasChanges {
                    Text(settings.t("precision.opening.noChanges"))
                        .font(Typography.meta)
                        .foregroundStyle(Palette.inkSecondary)
                }

                if draft.hasChanges {
                    Toggle(settings.t("precision.inline.laser"), isOn: $draft.laserVerified)
                        .tint(Palette.accent)
                        .accessibilityIdentifier("precision.opening.laser")
                }

                Button(action: onConfirm) {
                    HStack {
                        if isSaving { ProgressView().tint(Palette.onAccent) }
                        Text(settings.t(isSaving ? "precision.inline.saving" : "precision.opening.confirm"))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .disabled(preview?.isValid != true || !draft.hasChanges || draft.requiresReferenceForChanges || isSaving)
                .accessibilityIdentifier("precision.opening.confirm")
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.surface)
        .presentationDetents([.height(390), .large], selection: $selectedDetent)
        .onChange(of: showsOtherMeasurements) { _, isExpanded in
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDetent = isExpanded || dynamicTypeSize.isAccessibilitySize ? .large : .height(390)
            }
        }
        .task(id: dynamicTypeSize) {
            if dynamicTypeSize.isAccessibilitySize { selectedDetent = .large }
        }
    }

    private var title: String {
        let key: String = switch openingKind {
        case .door: "precision.opening.doorTitle"
        case .window: "precision.opening.windowTitle"
        case .opening: "precision.opening.genericTitle"
        }
        return settings.t(key, String(ordinal))
    }

    private func conflictText(_ preview: OpeningEditPreview) -> String {
        if preview.resolution.conflicts.contains(where: { $0.code == .overlappingOpenings }) {
            return settings.t("precision.opening.overlap")
        }
        if preview.resolution.conflicts.contains(where: { $0.code == .contradictoryMeasurements }) {
            return settings.t("precision.opening.protectedConflict")
        }
        return settings.t("precision.opening.invalid")
    }
}

private struct OpeningSheetHeader: View {
    let title: String
    let onClose: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack {
            Text(title)
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityIdentifier("precision.opening.title")
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").frame(width: 46, height: 46)
            }
            .frame(minWidth: 46, minHeight: 46)
            .contentShape(.rect)
            .buttonStyle(.plain)
            .accessibilityLabel(settings.t("common.close"))
            .accessibilityIdentifier("precision.opening.close")
        }
    }
}

private struct OpeningReferencePicker: View {
    @Binding var selection: OpeningReferenceEndpoint?
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(settings.t("precision.opening.whichCorner"))
                .font(Typography.control)
            Picker(settings.t("precision.opening.whichCorner"), selection: $selection) {
                Text(settings.t("precision.opening.wallStart")).tag(OpeningReferenceEndpoint?.some(.wallStart))
                Text(settings.t("precision.opening.wallEnd")).tag(OpeningReferenceEndpoint?.some(.wallEnd))
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("precision.opening.reference")
        }
    }
}

private struct OpeningPrimaryFields: View {
    let openingKind: WallOpeningKind
    @Binding var draft: OpeningMeasurementDraft
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 12) {
            if draft.referenceEndpoint == .wallEnd {
                MillimeterField(label: offsetLabel, text: $draft.endOffsetMillimeters, identifier: "precision.opening.offset")
            } else {
                MillimeterField(label: offsetLabel, text: $draft.startOffsetMillimeters, identifier: "precision.opening.offset")
            }
            MillimeterField(label: widthLabel, text: $draft.widthMillimeters, identifier: "precision.opening.width")
        }
    }

    private var offsetLabel: String {
        settings.t(openingKind == .window ? "precision.opening.windowOffset" : "precision.opening.doorOffset")
    }

    private var widthLabel: String {
        settings.t(openingKind == .window ? "precision.opening.windowWidth" : "precision.opening.doorWidth")
    }
}

private struct OpeningOptionalFields: View {
    let openingKind: WallOpeningKind
    @Binding var draft: OpeningMeasurementDraft
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 12) {
            if openingKind == .window {
                MillimeterField(label: settings.t("precision.opening.sill"), text: $draft.lowerElevationMillimeters,
                                identifier: "precision.opening.sill")
                MillimeterField(label: settings.t("precision.opening.windowHeight"), text: $draft.heightMillimeters,
                                identifier: "precision.opening.height")
                MillimeterField(label: settings.t("precision.opening.top"), text: $draft.topElevationMillimeters,
                                identifier: "precision.opening.top")
            } else if openingKind == .door {
                MillimeterField(label: settings.t("precision.opening.doorHeight"), text: $draft.heightMillimeters,
                                identifier: "precision.opening.height")
                MillimeterField(label: settings.t("precision.opening.threshold"), text: $draft.lowerElevationMillimeters,
                                identifier: "precision.opening.threshold")
            }

            if draft.referenceEndpoint == .wallEnd {
                ReadOnlyMillimeterValue(label: settings.t("precision.opening.startOffset"), value: draft.startOffsetMillimeters)
            } else {
                ReadOnlyMillimeterValue(label: settings.t("precision.opening.endOffset"), value: draft.endOffsetMillimeters)
            }
        }
    }
}

private struct ReadOnlyMillimeterValue: View {
    let label: String
    let value: String

    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack {
            Text(label)
                .font(Typography.meta)
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            Text(value.isEmpty ? settings.t("precision.opening.unknown") : "\(value) mm")
                .font(.body.monospaced())
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MillimeterField: View {
    let label: String
    @Binding var text: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(Typography.meta).foregroundStyle(Palette.inkSecondary)
            HStack {
                TextField(label, text: $text)
                    .keyboardType(.numberPad)
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(identifier)
                Text("mm").font(Typography.control).foregroundStyle(Palette.inkSecondary)
            }
        }
    }
}
