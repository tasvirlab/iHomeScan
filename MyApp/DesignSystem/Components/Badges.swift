import SwiftUI

/// Small pill marking placeholder content as sample data.
struct SampleBadge: View {
    @Environment(AppSettings.self) private var settings
    var onMaterial = false

    var body: some View {
        Text(settings.t("common.sampleData"))
            .font(Typography.badge)
            .foregroundStyle(Palette.inkSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                if onMaterial {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))
                } else {
                    Capsule().fill(Palette.surface)
                }
            }
    }
}

/// Section header label used above grouped content.
struct SectionLabel: View {
    let title: String
    var font: Font = Typography.sectionHeader

    var body: some View {
        Text(title)
            .font(font)
            .foregroundStyle(Palette.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.titleEdge)
            .accessibilityAddTraits(.isHeader)
    }
}
