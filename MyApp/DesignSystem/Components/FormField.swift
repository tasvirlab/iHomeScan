import SwiftUI

/// Labeled text input in the design's recessed-surface style.
struct FormField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    /// Unit shown at the trailing edge, e.g. "mm" or "m²".
    var unit: String?
    var isNumeric = false
    var hasError = false
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.settingsHeader)
                .foregroundStyle(hasError ? Palette.error : Palette.inkSecondary)
            HStack(spacing: 8) {
                TextField(prompt, text: $text, axis: axis)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(axis == .vertical ? 2...5 : 1...1)
                    .keyboardType(isNumeric ? .decimalPad : .default)
                    .autocorrectionDisabled(isNumeric)
                if let unit {
                    Text(unit)
                        .font(Typography.measurement)
                        .foregroundStyle(Palette.inkTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Palette.surface, in: .rect(cornerRadius: Radius.small))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.small)
                    .strokeBorder(hasError ? Palette.error : .clear, lineWidth: 1)
            )
        }
        .accessibilityElement(children: .combine)
    }
}

/// Full-width primary (accent) or secondary (surface) action button.
struct ActionButton: View {
    enum Kind { case primary, secondary, destructive }

    let title: String
    var systemImage: String?
    var kind: Kind = .primary
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(Typography.button)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(background, in: .rect(cornerRadius: Radius.medium))
        }
        .buttonStyle(.pressable)
        .disabled(isLoading)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Palette.onAccent
        case .secondary: Palette.ink
        case .destructive: Palette.error
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Palette.accent
        case .secondary, .destructive: Palette.surface
        }
    }
}
