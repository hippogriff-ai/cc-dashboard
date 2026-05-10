// One row in the Restore tab's left list pane. Ports the inner row of
// docs/ux-design/screens.jsx::RestoreTab (lines 60–83). Two-line layout:
//
//   line 1:  [urgency icon]  repo
//   line 2:  branch  · +<dirty>  · cwd missing  (any of the trailing pieces optional)
//
// Right edge: relative-time label.
//
// Visual states:
//   * selected → `theme.bgElevHover` background + 2pt accent inset bar on the
//     left edge (matches `.restore-row.selected box-shadow: 2px 0 0 0 inset`).
//   * `cwdMissing` → 0.5 opacity (matches `.restore-row.dim`).
//
// `cwdMissing` is computed once at row construction by the parent and passed
// in (rather than re-checking the filesystem in `body`) so `body` stays pure
// and SwiftUI can re-render the row freely without disk I/O.
import SwiftUI

struct RestoreRow: View {
    let repo: RecentRepo
    let isSelected: Bool
    let cwdMissing: Bool
    var onTap: () -> Void
    @Environment(\.theme) private var theme

    private var urgencyColor: Color {
        switch repo.event {
        case .permissionPending: return theme.uPermission
        case .toolFailed: return theme.uFailed
        case .ask: return theme.uAsk
        case .working: return theme.uWorking
        case .idleAfterComplete: return theme.uIdle
        case .clear: return theme.uClear
        }
    }

    private var urgencyIcon: IconName {
        switch repo.event {
        case .permissionPending: return .permission
        case .toolFailed: return .failed
        case .ask: return .ask
        case .working: return .working
        case .idleAfterComplete: return .idle
        case .clear: return .clear
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // 2pt accent bar on the left edge when selected. Always reserve
            // the 2pt slot so selection toggling doesn't shift row content
            // horizontally — invisible (clear) when not selected.
            Rectangle()
                .fill(isSelected ? theme.accent : Color.clear)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Icon(name: urgencyIcon, size: 11).foregroundColor(urgencyColor)
                    Text(repo.repo)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let branch = repo.branch, !branch.isEmpty {
                        Text(branch)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.fgSecondary)
                            .lineLimit(1)
                    }
                    if repo.dirty > 0 {
                        Text("+\(repo.dirty)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.uPermission)
                    }
                    if cwdMissing {
                        Text("· cwd missing")
                            .font(.system(size: 11))
                            .foregroundColor(theme.fgTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            Text(RelTime.format(repo.lastActivity))
                .font(.system(size: 11))
                .foregroundColor(theme.fgTertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .padding(.trailing, 10)
        .background(isSelected ? theme.bgElevHover : Color.clear)
        .opacity(cwdMissing ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
