import SwiftUI

struct InlinePrecisionMeasurementSheet: View {
    let currentMillimeters: String
    let currentLabelKey: String
    @Binding var input: String
    @Binding var laserVerified: Bool
    @Binding var anchor: WallLengthAnchorStrategy?
    let requiresAnchorChoice: Bool
    let hasValidPreview: Bool
    let hasConflict: Bool
    let isSaving: Bool
    let onConfirm: () -> Void
    let onClose: () -> Void

    @Environment(AppSettings.self) private var settings
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InlineMeasurementHeader(onClose: onClose)
            Text(settings.t(currentLabelKey, currentMillimeters))
                .font(Typography.body)
                .foregroundStyle(Palette.inkSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField(settings.t("precision.inline.input"), text: $input)
                    .keyboardType(.decimalPad)
                    .font(.system(.title2, design: .monospaced, weight: .semibold))
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .accessibilityIdentifier("precision.inline.input")
                Text("mm")
                    .font(Typography.control)
                    .foregroundStyle(Palette.inkSecondary)
            }

            Toggle(settings.t("precision.inline.laser"), isOn: $laserVerified)
                .tint(Palette.accent)
                .accessibilityIdentifier("precision.inline.laser")

            if requiresAnchorChoice {
                VStack(alignment: .leading, spacing: 8) {
                    Text(settings.t("precision.inline.anchorQuestion"))
                        .font(Typography.rowTitle)
                    Picker(settings.t("precision.editor.anchor"), selection: $anchor) {
                        Text(settings.t("precision.inline.anchorStart")).tag(WallLengthAnchorStrategy?.some(.keepStart))
                        Text(settings.t("precision.inline.anchorEnd")).tag(WallLengthAnchorStrategy?.some(.keepEnd))
                    }
                    .pickerStyle(.segmented)
                }
            }

            if hasConflict {
                Label(settings.t("precision.inline.conflict"), systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.error)
            } else if !input.isEmpty && PrecisionMeasurementInput.meters(fromMillimeters: input) == nil {
                Label(settings.t("precision.editor.invalidMeasurement"), systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.error)
            }

            Button(action: onConfirm) {
                HStack {
                    if isSaving { ProgressView().tint(Palette.onAccent) }
                    Text(settings.t(isSaving ? "precision.inline.saving" : "precision.inline.confirm"))
                }
                .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .disabled(!hasValidPreview || hasConflict || isSaving)
            .accessibilityIdentifier("precision.inline.confirm")
        }
        .padding(20)
        .background(Palette.surface)
        .onAppear { inputFocused = true }
    }
}

private struct InlineMeasurementHeader: View {
    let onClose: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack {
            Text(settings.t("precision.inline.title"))
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.ink)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.t("common.close"))
            .accessibilityIdentifier("precision.inline.close")
        }
    }
}
