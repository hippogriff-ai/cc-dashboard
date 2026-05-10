// Lightweight observable wrapper around `UNUserNotificationCenter.current()
// .getNotificationSettings()`. Polled on popover open (and on Settings
// section appear) so the user sees the current authorization state without
// us having to subscribe to a system push that doesn't exist for this. The
// auth-denied UI affordance in `SettingsView.notificationsSection` reads
// `isDenied` and renders an inline warning + "Open System Settings" button
// when true. Loop 38 — closes the deferred Loop 30 MEDIUM.
import Foundation
import UserNotifications
import os

@MainActor
final class NotificationAuthStatus: ObservableObject {
    /// `true` only when the user has explicitly denied via the system prompt
    /// or the Notifications pane. `.notDetermined` (first launch, no decision
    /// yet) and `.authorized` / `.provisional` / `.ephemeral` all render as
    /// `false` — we only warn when there's an actionable state to show.
    @Published private(set) var isDenied: Bool = false

    private static let logger = Logger(
        subsystem: "dev.vcheval.cc-dashboard",
        category: "NotificationAuthStatus"
    )

    /// Refresh the cached state from the system. The completion handler runs
    /// on a UNUserNotificationCenter-owned queue, so we hop back to MainActor
    /// before mutating `@Published` state.
    func refresh() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let denied = settings.authorizationStatus == .denied
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isDenied != denied {
                    Self.logger.info("auth status changed to denied=\(denied, privacy: .public)")
                    self.isDenied = denied
                }
            }
        }
    }
}
