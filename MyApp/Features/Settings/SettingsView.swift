import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return settings.t("settings.version", version, build)
    }

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(settings.t("tab.settings"))
                    .font(Typography.screenTitle)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, Spacing.titleEdge)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
                    .accessibilityAddTraits(.isHeader)

                profileCard

                header("settings.language", top: 26)
                SegmentedPill(
                    options: AppLanguage.allCases.map { .init(value: $0, title: $0.displayName) },
                    selection: $settings.language
                )
                .padding(.horizontal, Spacing.screenEdge)

                header("settings.appearance")
                SegmentedPill(
                    options: AppAppearance.allCases.map { .init(value: $0, title: settings.t($0.titleKey)) },
                    selection: $settings.appearance
                )
                .padding(.horizontal, Spacing.screenEdge)

                header("settings.units")
                SegmentedPill(
                    options: MeasurementUnit.allCases.map { .init(value: $0, title: settings.t($0.titleKey)) },
                    selection: $settings.units
                )
                .padding(.horizontal, Spacing.screenEdge)

                header("settings.about")
                aboutCard
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func header(_ key: String, top: CGFloat = 22) -> some View {
        SectionLabel(title: settings.t(key), font: Typography.settingsHeader)
            .padding(.top, top)
            .padding(.bottom, 8)
    }

    /// Profile editing arrives in a later phase; the card shows the design's call to action.
    private var profileCard: some View {
        Button { model.showToast("toast.notAvailable") } label: {
            HStack(spacing: 14) {
                AvatarView(size: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.t("settings.profile.title"))
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(settings.t("settings.profile.body"))
                        .font(Typography.body)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.inkTertiary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .cardSurface()
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, Spacing.screenEdge)
    }

    private var aboutCard: some View {
        HStack(alignment: .top, spacing: 14) {
            BrandMark(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "iHomeScan")
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.ink)
                Text(versionText)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.inkSecondary)
                Text(settings.t("settings.aboutBody"))
                    .font(Typography.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .cardSurface()
        .padding(.horizontal, Spacing.screenEdge)
        .accessibilityElement(children: .combine)
    }
}
