import SwiftUI

/// Graphite capsule message that appears at the top of the screen and dismisses itself.
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.onGraphite)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Palette.graphite, in: .capsule)
            .overlay(Capsule().strokeBorder(Palette.onGraphite.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 15, y: 10)
            .padding(.horizontal, 24)
            .accessibilityAddTraits(.isStaticText)
    }
}

extension View {
    /// Presents the app model's current toast over this view.
    func toastOverlay(_ model: AppModel, settings: AppSettings) -> some View {
        overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(message: settings.t(toast.messageKey))
                    // Below the 52–44 pt header / navigation bar so it never covers their buttons.
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        AccessibilityNotification.Announcement(settings.t(toast.messageKey)).post()
                        try? await Task.sleep(for: .seconds(2.2))
                        guard model.toast?.id == toast.id else { return }
                        withAnimation(.easeIn(duration: 0.2)) { model.toast = nil }
                    }
            }
        }
    }
}
