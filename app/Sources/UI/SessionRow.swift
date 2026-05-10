// One row per live session in the popover's Live tab. Ports
// docs/ux-design/components.jsx::SessionRow.
//
// Layout (left → right):
//   * 2pt urgency tick (vertical bar) colored by `session.event`
//   * urgency icon + repo (medium weight) + branch (secondary, optional)
//   * status reason on line 2 (secondary, optional, single line)
//   * relative time on the right (tertiary)
//   * optional nav badge (1–9) in the corner when keyboard nav is active
//
// 5-state event mapping (urgency icon + color come from `theme.u*`):
//   PERMISSION_PENDING  → `theme.uPermission` + `.permission` icon (urgent bg)
//   TOOL_FAILED         → `theme.uFailed`     + `.failed` icon     (urgent bg)
//   ASK                 → `theme.uAsk`        + `.ask` icon
//   WORKING             → `theme.uWorking`    + `.working` icon
//   IDLE_AFTER_COMPLETE → `theme.uIdle`       + `.idle` icon
//   CLEAR               → `theme.uClear`      + `.clear` icon
//
// Urgent rows (PERMISSION_PENDING / TOOL_FAILED) render with `theme.bgRowUrgent`
// regardless of focus; non-urgent focused rows use `theme.bgElevHover`.
// Stale sessions (no activity for >30min) are dimmed to 0.6 opacity.
import SwiftUI

struct SessionRow: View {
    let session: LiveSession
    let isFocused: Bool
    let navIndex: Int?
    let isStale: Bool
    /// Primary-action tap (the row body). Wired to "focus the terminal" —
    /// pressing the row should raise the matching Ghostty window. When nil,
    /// the row renders without a tap affordance.
    var onTap: (() -> Void)? = nil
    /// Secondary-action tap on the trailing info chevron. Pushes Session
    /// Detail. Separated from `onTap` so primary clicks never accidentally
    /// open the detail view. When nil, the chevron is hidden.
    var onInfoTap: (() -> Void)? = nil
    @Environment(\.theme) private var theme

    private var urgencyColor: Color {
        switch session.event {
        case .permissionPending: return theme.uPermission
        case .toolFailed: return theme.uFailed
        case .ask: return theme.uAsk
        case .working: return theme.uWorking
        case .idleAfterComplete: return theme.uIdle
        case .clear: return theme.uClear
        }
    }

    private var urgencyIcon: IconName {
        switch session.event {
        case .permissionPending: return .permission
        case .toolFailed: return .failed
        case .ask: return .ask
        case .working: return .working
        case .idleAfterComplete: return .idle
        case .clear: return .clear
        }
    }

    private var isUrgent: Bool {
        session.event == .permissionPending || session.event == .toolFailed
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(urgencyColor).frame(width: 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Icon(name: urgencyIcon).foregroundColor(urgencyColor)
                    Text(session.repo).fontWeight(.medium)
                    // Branch is optional — empty Text would render as a dead
                    // gap in the line and throw off horizontal rhythm.
                    if let branch = session.branch, !branch.isEmpty {
                        Text(branch)
                            .foregroundColor(theme.fgSecondary)
                            .font(.system(size: 11.5))
                    }
                }
                // Reason is also optional — same rationale as branch above:
                // skipping the second line entirely (rather than emitting a
                // blank Text) keeps the row's vertical rhythm correct.
                if !session.reason.isEmpty {
                    Text(session.reason)
                        .font(.system(size: 11.5))
                        .foregroundColor(theme.fgSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(RelTime.format(session.lastActivity))
                .font(.system(size: 11))
                .foregroundColor(theme.fgTertiary)
            if let n = navIndex {
                Text(String(n))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(4)
                    .background(theme.accent)
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
            // Trailing info chevron — pushes Session Detail. Separated from
            // the row body so primary clicks (focus terminal) and detail-open
            // don't share a hit target. The HStack `Spacer` above pushes it
            // to the trailing edge; the local `Rectangle` content shape gives
            // the chevron a generous tap area without enlarging the visual.
            if let onInfoTap {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundColor(theme.fgTertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onInfoTap)
                    .help("Show session details")
                    .accessibilityLabel("Show session details")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(isUrgent ? theme.bgRowUrgent : (isFocused ? theme.bgElevHover : Color.clear))
        .opacity(isStale ? 0.6 : 1.0)
        .modifier(ConditionalTapGesture(action: onTap))
    }
}

/// Attaches a tap-gesture only when an action closure is provided. Avoids the
/// "row appears tappable but does nothing" silent-failure pattern when the
/// caller hasn't wired a handler yet.
private struct ConditionalTapGesture: ViewModifier {
    let action: (() -> Void)?
    func body(content: Content) -> some View {
        if let action {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
        } else {
            content
        }
    }
}

/// Pure relative-time helpers, lifted out of `SessionRow` so unit tests can
/// exercise them without instantiating SwiftUI views. `now` is injectable so
/// tests can pin a deterministic reference time; production callers omit it
/// and get `Date()` at call-time.
enum RelTime {
    /// Format a millisecond-epoch timestamp as a short relative-time label
    /// ("now", "30s ago", "5m ago", "2h ago", "3d ago"). Always rounds toward
    /// the smaller unit (no half-up rounding) so transitions are monotonic.
    static func format(_ msEpoch: Double, now: Date = Date()) -> String {
        // Sentinel for missing or zero-init timestamps: a backend response
        // that emits `lastActivity: 0` would otherwise render "20597d ago"
        // (~55 years), which is visually broken and obscures the real cause.
        if msEpoch <= 0 { return "—" }
        let s = Int((now.timeIntervalSince1970 * 1000 - msEpoch) / 1000)
        // Negative seconds = backend timestamp is in the future. Most likely
        // cause is client clock skew. Render as "now" rather than "-30s ago"
        // (which is meaningless to users) but preserve the no-information
        // signal — the row simply doesn't claim an age.
        if s < 5 { return "now" }
        if s < 60 { return "\(s)s ago" }
        let m = s / 60
        if m < 60 { return "\(m)m ago" }
        let h = m / 60
        if h < 24 { return "\(h)h ago" }
        return "\(h / 24)d ago"
    }

    /// Whether a session is "stale" — i.e. no activity for >30 minutes by
    /// default. Pulled into this enum for the same testability reason as
    /// `format(_:now:)`.
    static func isStale(_ msEpoch: Double, now: Date = Date(), thresholdSec: TimeInterval = 30 * 60) -> Bool {
        (now.timeIntervalSince1970 * 1000 - msEpoch) > thresholdSec * 1000
    }
}
