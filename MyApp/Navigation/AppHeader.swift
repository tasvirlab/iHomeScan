import SwiftUI

/// Top bar for the main tabs: brand on Home, plus language menu and profile button.
struct AppHeader: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = settings

        HStack(spacing: 8) {
            if model.selectedTab == .home {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 9) {
                        BrandMark()
                        Text(verbatim: "iHomeScan")
                            .font(Typography.brand)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    BrandMark()
                }
                .transition(.opacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "iHomeScan"))
                .accessibilityAddTraits(.isHeader)
            }

            Spacer()

            Menu {
                Picker(settings.t("a11y.language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.displayName).tag(language)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(verbatim: settings.language.code)
                        .font(.footnote.weight(.semibold))
                        .tracking(0.3)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(Palette.ink)
                .padding(.leading, 12)
                .padding(.trailing, 9)
                .frame(minHeight: 34)
                .background(Palette.surface, in: .capsule)
            }
            .accessibilityLabel(settings.t("a11y.language"))
            .accessibilityValue(settings.language.displayName)

            Button {
                model.selectedTab = .settings
            } label: {
                AvatarView()
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(settings.t("a11y.profile"))
        }
        .padding(.leading, Spacing.titleEdge)
        .padding(.trailing, Spacing.screenEdge)
        .frame(minHeight: 52)
    }
}
