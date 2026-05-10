// Translucent overlay rendered while navigate-mode is active. Numbered
// badges (1–9) are drawn by `SessionRow` itself (it already accepts a
// `navIndex` parameter that `LiveTab` populates from the same `navMode`
// binding); this overlay's only job is to (a) dim the rest of the chrome
// so the badges read as the active affordance, and (b) carry an
// accessibility-friendly hint label.
//
// The overlay does NOT install its own keyboard monitor — `KeyboardMonitor`
// already owns the popover-wide keyDown handle, and routing 1–9 through
// two separate code paths would risk one half going stale. The resolver
// returns `.jumpTo(n)` when navMode is on; `PopoverController` consumes
// it, drives the focus call, and flips navMode off.
import SwiftUI

struct NavigateOverlay: View {
    /// Whether nav-mode is currently active. When false the overlay
    /// renders nothing — the modifier form below collapses to `EmptyView`
    /// so it is free to keep mounted in the view tree.
    let active: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        if active {
            ZStack(alignment: .bottom) {
                // Translucent dim layer. Material is theme-aware via the
                // system blur; tinting with `theme.bgWindow` at low opacity
                // keeps it consistent with the popover chrome.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.55)
                    .allowsHitTesting(false)
                hintBar
            }
            .accessibilityLabel("Navigate mode active. Press 1 to 9 to focus a session, or escape to exit.")
            .transition(.opacity)
        } else {
            EmptyView()
        }
    }

    private var hintBar: some View {
        HStack(spacing: 6) {
            Text("Navigate")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text("1-9 jump · esc cancel")
                .font(.system(size: 10.5))
                .foregroundColor(theme.fgSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.bgElev.opacity(0.92))
        .clipShape(Capsule())
        .padding(.bottom, 10)
    }
}

/// View modifier so callers wire the overlay with one line:
///   `someView.navigateOverlay(active: navMode)`
/// Keeps the dim-layer + hint-bar a single, consistent visual treatment
/// across whichever container ends up hosting it (today: `PopoverShell`'s
/// inner content, via `PopoverController`).
extension View {
    func navigateOverlay(active: Bool) -> some View {
        self.overlay(NavigateOverlay(active: active))
    }
}
