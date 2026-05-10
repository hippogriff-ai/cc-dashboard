// Popover header: stacked-logo + "cc-dash" title + count text on the left,
// QuietPill on the right. Ports docs/ux-design/components.jsx `PopHeader` /
// styles.css `.pop-header`.
import SwiftUI

struct PopHeader: View {
    let liveCount: Int
    let attentionCount: Int
    /// Connection state from `PollingStore.connectionStatus`. We only render
    /// chrome for `.stale` — the other two states are silent.
    let connection: ConnectionStatus
    @Binding var quiet: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Icon(name: .stackFilled, size: 14, tint: theme.accent)
                Text("cc-dash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.fg)
                Text("\(liveCount) live · \(attentionCount) need attention")
                    .font(.system(size: 11))
                    .foregroundColor(theme.fgTertiary)
                    .monospacedDigit()
                if case .stale(let elapsed) = connection {
                    // Inline pip + duration. `theme.uFailed` matches the
                    // attention-failed urgency so the visual language is
                    // consistent with row-level error states.
                    HStack(spacing: 4) {
                        Circle().fill(theme.uFailed).frame(width: 6, height: 6)
                        Text("disconnected · \(elapsed)s")
                            .font(.system(size: 11))
                            .foregroundColor(theme.uFailed)
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Backend disconnected for \(elapsed) seconds")
                }
            }
            Spacer()
            QuietPill(quiet: $quiet)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.separator)
                .frame(height: 1)
        }
    }
}
