// Toggle pill from docs/ux-design/components.jsx `QuietPill`. Tapping flips
// `quiet`. Visual rules ported from styles.css `.quiet-pill`:
//   - Active (quiet=false): dot tinted `theme.uWorking`, bolt glyph + "Active"
//   - Quiet  (quiet=true):  dot tinted `theme.uIdle`, moon glyph + "Quiet"
// The dot is a 6pt circle. Capsule background uses `theme.bgElev`; a quiet
// pill swaps in `theme.fgQuaternary` border to highlight the off state.
import SwiftUI

struct QuietPill: View {
    @Binding var quiet: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: { quiet.toggle() }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(quiet ? theme.uIdle : theme.uWorking)
                    .frame(width: 6, height: 6)
                Icon(name: quiet ? .moon : .bolt, size: 11, tint: theme.fgSecondary)
                Text(quiet ? "Quiet" : "Active")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.fgSecondary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(theme.bgElev)
            )
            .overlay(
                Capsule().stroke(quiet ? theme.fgQuaternary : theme.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
