import SwiftUI

enum ScanMethod: String, Identifiable {
    case photo
    case lidar

    var id: String { rawValue }
}

/// Reusable pair of equally weighted scan choices used on Home and in the scan sheet.
struct ScanMethodCards: View {
    let isLidarSupported: Bool
    let accessibilityScope: String
    let onPhotoScan: () -> Void
    let onLidarScan: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 13) {
            ScanMethodCard(
                identifier: "\(accessibilityScope).photo",
                title: settings.t("scan.choice.photo.title"),
                summary: settings.t("scan.choice.photo.summary"),
                requirement: settings.t("scan.choice.photo.requirement"),
                systemImage: "camera.aperture",
                isEnabled: true,
                action: onPhotoScan
            )

            ScanMethodCard(
                identifier: "\(accessibilityScope).lidar",
                title: settings.t("scan.choice.lidar.title"),
                summary: settings.t("scan.choice.lidar.summary"),
                requirement: isLidarSupported
                    ? settings.t("scan.choice.lidar.available")
                    : settings.t("scan.choice.lidar.requirement"),
                systemImage: "viewfinder",
                isEnabled: isLidarSupported,
                action: onLidarScan
            )
        }
    }
}

struct ScanStartSection: View {
    let onPhotoScan: () -> Void
    let onLidarScan: () -> Void

    @Environment(AppSettings.self) private var settings
    private let isLidarSupported: Bool

    init(
        capabilities: any DeviceCapabilityChecking = RoomPlanCapabilityChecker(),
        onPhotoScan: @escaping () -> Void,
        onLidarScan: @escaping () -> Void
    ) {
        isLidarSupported = capabilities.isRoomCaptureSupported
        self.onPhotoScan = onPhotoScan
        self.onLidarScan = onLidarScan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(settings.t("scan.choice.section"))
                .font(Typography.sectionHeader)
                .foregroundStyle(Palette.inkSecondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            ScanMethodCards(
                isLidarSupported: isLidarSupported,
                accessibilityScope: "scan.home",
                onPhotoScan: onPhotoScan,
                onLidarScan: onLidarScan
            )
        }
        .padding(.horizontal, Spacing.screenEdge)
    }
}

struct ScanMethodSelectionSheet: View {
    let context: ScannerContext
    let onPhotoScan: () -> Void
    let onLidarScan: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let isLidarSupported: Bool

    init(
        context: ScannerContext,
        capabilities: any DeviceCapabilityChecking = RoomPlanCapabilityChecker(),
        onPhotoScan: @escaping () -> Void,
        onLidarScan: @escaping () -> Void
    ) {
        self.context = context
        isLidarSupported = capabilities.isRoomCaptureSupported
        self.onPhotoScan = onPhotoScan
        self.onLidarScan = onLidarScan
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    Text(settings.t("scan.choice.title"))
                        .font(Typography.sheetTitle)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    ScanMethodCards(
                        isLidarSupported: isLidarSupported,
                        accessibilityScope: "scan.picker",
                        onPhotoScan: onPhotoScan,
                        onLidarScan: onLidarScan
                    )
                }
                .padding(.horizontal, Spacing.screenEdge)
                .padding(.vertical, 21)
            }
            .scrollIndicators(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .foregroundStyle(Palette.ink)
                    .accessibilityLabel(settings.t("common.close"))
                }
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ScanMethodCard: View {
    let identifier: String
    let title: String
    let summary: String
    let requirement: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            icon
                            titleText
                            Spacer(minLength: 0)
                            chevron
                        }
                        details
                    }
                } else {
                    HStack(spacing: 8) {
                        icon
                        VStack(alignment: .leading, spacing: 4) {
                            titleText
                            details
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        chevron
                    }
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: Radius.card))
            .cardSurface()
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isEnabled ? .isButton : [])
        .accessibilityIdentifier(identifier)
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(isEnabled ? Palette.accentText : Palette.inkSecondary)
            .frame(width: 46, height: 46)
            .background(isEnabled ? Palette.accentTint : Palette.surface, in: .rect(cornerRadius: Radius.small))
            .accessibilityHidden(true)
    }

    private var titleText: some View {
        Text(title)
            .font(Typography.cardTitle)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary)
                .font(Typography.body)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(requirement)
                .font(Typography.meta)
                .foregroundStyle(isEnabled ? Palette.accentText : Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var chevron: some View {
        if isEnabled {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Palette.inkTertiary)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 28 : 44, height: 44)
                .accessibilityHidden(true)
        }
    }
}

#Preview("Scan choices · unsupported") {
    PreviewContainer {
        ScanStartSection(
            capabilities: PreviewScanCapabilities(isRoomCaptureSupported: false),
            onPhotoScan: {},
            onLidarScan: {}
        )
    }
}

#Preview("Scan choices · supported") {
    PreviewContainer(language: .uzbek) {
        ScanStartSection(
            capabilities: PreviewScanCapabilities(isRoomCaptureSupported: true),
            onPhotoScan: {},
            onLidarScan: {}
        )
    }
    .preferredColorScheme(.dark)
}

private struct PreviewScanCapabilities: DeviceCapabilityChecking {
    let isRoomCaptureSupported: Bool
    let isSimulator = true
}
