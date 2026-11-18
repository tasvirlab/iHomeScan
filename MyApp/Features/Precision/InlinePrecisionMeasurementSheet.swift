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

    private var wheelCenter: Int {
        let current = PrecisionMeasurementInput.meters(fromMillimeters: currentMillimeters)
            .map { Int(($0 * 1_000).rounded()) }
        return current ?? 1_000
    }

    private var wheelValues: ClosedRange<Int> {
        max(1, wheelCenter - 1_000)...min(100_000, wheelCenter + 1_000)
    }

    private var wheelSelection: Binding<Int> {
        Binding(
            get: {
                guard let meters = PrecisionMeasurementInput.meters(fromMillimeters: input) else {
                    return min(max(wheelCenter, wheelValues.lowerBound), wheelValues.upperBound)
                }
                return min(max(Int((meters * 1_000).rounded()), wheelValues.lowerBound), wheelValues.upperBound)
            },
            set: { input = String($0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
            InlineMeasurementHeader(onClose: onClose)
            Text(settings.t(currentLabelKey, currentMillimeters))
                .font(Typography.body)
                .foregroundStyle(Palette.inkSecondary)
                .accessibilityIdentifier("precision.inline.current")

            HStack(alignment: .center, spacing: 10) {
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

            if !inputFocused {
                HStack(spacing: 12) {
                    measurementStepButton(systemImage: "minus", delta: -1)

                    Picker(settings.t("precision.inline.input"), selection: wheelSelection) {
                        ForEach(wheelValues, id: \.self) { value in
                            Text(verbatim: "\(value) mm")
                                .font(.system(.title3, design: .monospaced, weight: .semibold))
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity, minHeight: 108, maxHeight: 108)
                    .clipped()
                    .accessibilityIdentifier("precision.inline.wheel")

                    measurementStepButton(systemImage: "plus", delta: 1)
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

            Toggle(settings.t("precision.inline.laser"), isOn: $laserVerified)
                .tint(Palette.accent)
                .accessibilityIdentifier("precision.inline.laser")
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.surface)
    }

    private func measurementStepButton(systemImage: String, delta: Int) -> some View {
        Button {
            inputFocused = false
            let current = wheelSelection.wrappedValue
            wheelSelection.wrappedValue = min(max(current + delta, wheelValues.lowerBound), wheelValues.upperBound)
        } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 48, height: 48)
                .background(Palette.card, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.ink)
        .accessibilityIdentifier(delta < 0 ? "precision.inline.decrement" : "precision.inline.increment")
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
                .accessibilityIdentifier("precision.inline.title")
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 46, height: 46)
            }
            .frame(minWidth: 46, minHeight: 46)
            .contentShape(.rect)
            .buttonStyle(.plain)
            .accessibilityLabel(settings.t("common.close"))
            .accessibilityIdentifier("precision.inline.close")
        }
    }
}
