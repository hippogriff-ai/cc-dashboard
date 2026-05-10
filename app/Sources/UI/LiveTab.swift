// Live tab body for the popover. Ports docs/ux-design/screens.jsx::LiveTab.
//
// Renders one of:
//   * empty state ("No live sessions / Start one with `claude` in any
//     terminal.") when `store.sessions` is empty
//   * a vertical scrolling list of `SessionRow`s, already sorted by
//     `PollingStore.sort(_:)` (ranker priority asc, then last activity desc)
//
// `navMode` and `focusedId` are wired through as `@Binding` so Phase 5 can
// hook keyboard navigation in without changing this view's API. Until then
// the call site passes constant bindings; the row's `navIndex` stays nil and
// `isFocused` stays false.
//
// Staleness is delegated to `RelTime.isStale(_:)` so the threshold lives in
// one place and is unit-tested.
import SwiftUI

struct LiveTab: View {
    @ObservedObject var store: PollingStore
    @Binding var navMode: Bool
    @Binding var focusedId: String?
    /// Primary row tap → focus the matching Ghostty terminal window.
    /// Wired by `PopoverController` to the existing `focus(session:)` path
    /// (FocusStrategy resolver from Task 31). When nil, rows aren't tappable.
    var onActivate: ((LiveSession) -> Void)? = nil
    /// Trailing info-chevron tap → push Session Detail. Separated from the
    /// row body so primary clicks never accidentally open the detail view.
    var onOpenDetail: ((LiveSession) -> Void)? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        // Distinguish "polling broken" from "no sessions yet". Without this
        // branch, a backend outage and an empty workspace render identically
        // ("No live sessions"), and the user is told to start a session when
        // they may already have one running and the dashboard is just blind.
        if let err = store.lastError, store.sessions.isEmpty {
            errorState(err)
        } else if store.sessions.isEmpty {
            emptyState
        } else {
            sessionList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Icon(name: .stack, size: 22).foregroundColor(theme.fgTertiary)
            Text("No live sessions").fontWeight(.semibold)
            // SwiftUI Text concatenation: each operand is a Text with its own
            // font/foregroundColor; the `+` produces a single multi-styled
            // run that wraps as one paragraph.
            Text("Start one with ").foregroundColor(theme.fgSecondary)
                + Text("claude").font(.system(.body, design: .monospaced))
                + Text(" in any terminal.").foregroundColor(theme.fgSecondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Icon(name: .warning, size: 14).foregroundColor(theme.uFailed)
                Text("Can't reach backend").fontWeight(.semibold)
            }
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.fgSecondary)
                .lineLimit(4)
                .truncationMode(.tail)
            Text("Retrying every 2s. Check Console.app under `dev.vcheval.cc-dashboard` for details.")
                .font(.system(size: 11))
                .foregroundColor(theme.fgTertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(store.sessions.enumerated()), id: \.element.id) { idx, s in
                    SessionRow(
                        session: s,
                        isFocused: focusedId == s.sessionId,
                        navIndex: navMode && idx < 9 ? idx + 1 : nil,
                        isStale: RelTime.isStale(s.lastActivity),
                        // Primary tap = focus terminal; chevron = detail.
                        // Each handler is wired only when the caller provided
                        // it, so an unwired affordance never silently no-ops.
                        onTap: onActivate.map { handler in { handler(s) } },
                        onInfoTap: onOpenDetail.map { handler in { handler(s) } }
                    )
                    // `Divider().background(...)` ignores the background tint
                    // (Divider draws a translucent system gray); a 1pt
                    // Rectangle filled with the theme's separator color gives
                    // a visible, theme-aware separator line.
                    Rectangle()
                        .fill(theme.separator)
                        .frame(height: 1)
                }
            }
        }
    }
}
