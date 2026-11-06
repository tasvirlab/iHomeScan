import SwiftUI

/// Summary of a real, finished RoomPlan scan. Shows only what RoomPlan detected; measurements
/// are explicitly marked as not processed yet, and the scan is clearly marked as not saved.
struct ScanResultView: View {
    let summary: RoomScanSummary
    let completeness: RoomPlanGeometryMetadata.Completeness
    let savedAssociation: SavedScanAssociation?
    let onSave: () -> Void
    let onScanAgain: () -> Void
    let onDiscard: () -> Void
    let onOpenProject: () -> Void

    @Environment(AppSettings.self) private var settings

    private var counts: [(key: String, value: Int, symbol: String)] {
        [
            ("scan.result.walls", summary.walls, "square.split.bottomrightquarter"),
            ("scan.result.doors", summary.doors, "door.left.hand.open"),
            ("scan.result.windows", summary.windows, "window.horizontal"),
            ("scan.result.openings", summary.openings, "rectangle.portrait.arrowtriangle.2.outward"),
            ("scan.result.objects", summary.objects, "sofa"),
            ("scan.result.floors", summary.floors, "square.dashed"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Palette.success)
                        Text(settings.t("scan.result.title"))
                            .font(Typography.screenTitle)
                            .foregroundStyle(Palette.ink)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    Text(settings.t("scan.result.subtitle"))
                        .font(Typography.body)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.horizontal, Spacing.titleEdge - Spacing.screenEdge)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text(settings.t("scan.result.detected"))
                        .font(Typography.settingsHeader)
                        .foregroundStyle(Palette.inkSecondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(counts, id: \.key) { item in
                            countTile(titleKey: item.key, value: item.value, symbol: item.symbol)
                        }
                    }
                    HStack {
                        Text(settings.t("scan.result.measurements"))
                            .font(Typography.body)
                            .foregroundStyle(Palette.inkSecondary)
                        Spacer(minLength: 8)
                        Text(settings.t("scan.result.measurements.value"))
                            .font(Typography.rowTitle)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    .padding(.top, 4)
                    .accessibilityElement(children: .combine)
                }
                .padding(16)
                .cardSurface()

                if completeness != .complete {
                    ScanResultNotice(
                        systemImage: "exclamationmark.triangle",
                        title: settings.t("scan.result.incomplete.title"),
                        message: settings.t("scan.result.incomplete.body")
                    )
                }

                if let savedAssociation {
                    ScanResultNotice(
                        systemImage: "checkmark.seal.fill",
                        title: settings.t("scan.saved.title"),
                        message: settings.t(
                            "scan.saved.body",
                            savedAssociation.projectName,
                            savedAssociation.roomName
                        ),
                        isSuccess: true
                    )
                } else {
                    ScanResultNotice(
                        systemImage: "externaldrive",
                        title: settings.t("scan.result.readyToSave.title"),
                        message: settings.t("scan.result.readyToSave.body")
                    )
                }

                VStack(spacing: 10) {
                    if savedAssociation == nil {
                        ActionButton(
                            title: settings.t("scan.save.action"),
                            systemImage: "square.and.arrow.down",
                            action: onSave
                        )
                    } else {
                        ActionButton(
                            title: settings.t("scan.saved.openProject"),
                            systemImage: "folder",
                            action: onOpenProject
                        )
                    }
                    ActionButton(
                        title: settings.t("scan.result.again"),
                        systemImage: "arrow.counterclockwise",
                        kind: .secondary,
                        action: onScanAgain
                    )
                    ActionButton(
                        title: settings.t(savedAssociation == nil ? "scan.discard.action" : "common.close"),
                        kind: savedAssociation == nil ? .destructive : .secondary,
                        action: onDiscard
                    )
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, Spacing.screenEdge)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background.ignoresSafeArea())
    }

    private func countTile(titleKey: String, value: Int, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.accentText)
                .frame(width: 34, height: 34)
                .background(Palette.accentTint, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.formatted(.number.locale(settings.locale)))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                Text(settings.t(titleKey))
                    .font(Typography.meta)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.small))
        .accessibilityElement(children: .combine)
    }
}

private struct ScanResultNotice: View {
    let systemImage: String
    let title: String
    let message: String
    var isSuccess = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(isSuccess ? Palette.success : Palette.accentText)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.ink)
                Text(message)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accentTint, in: .rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
    }
}

/// Localized explanation of why a scan produced no result, with the relevant next step.
struct ScanFailureView: View {
    let failure: RoomScanFailure
    let onRetry: () -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: failure == .deviceTooHot ? "thermometer.high" : "exclamationmark.triangle")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Palette.accentText)
                    .frame(width: 84, height: 84)
                    .background(Palette.accentTint, in: .circle)
                    .accessibilityHidden(true)
                    .padding(.top, 48)

                VStack(spacing: 8) {
                    Text(settings.t(failure.titleKey))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.ink)
                    Text(settings.t(failure.bodyKey))
                        .font(Typography.body)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)

                Text(settings.t("scan.failure.nothingSaved"))
                    .font(Typography.meta)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    if failure == .cameraPermissionDenied {
                        ActionButton(title: settings.t("scanner.openSettings"), systemImage: "gear", action: onOpenSettings)
                    } else if failure.isRetryable {
                        ActionButton(title: settings.t("scanner.retry"), systemImage: "arrow.clockwise", action: onRetry)
                    }
                    ActionButton(title: settings.t("common.close"), kind: .secondary, action: onClose)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, Spacing.titleEdge)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
    }
}
