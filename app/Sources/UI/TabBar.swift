// Three-tab bar (Live / Restore / Settings). Active tab gets a 2pt accent
// underline + foreground tint per styles.css `.tab.active`. Inactive tabs
// render `theme.fgSecondary` text. The tab enum is exposed at module scope so
// the popover root view can own its `@State`.
import SwiftUI

enum PopoverTab: String, CaseIterable, Hashable, CustomStringConvertible {
    case live, restore, settings

    var description: String {
        switch self {
        case .live: return "Live"
        case .restore: return "Restore"
        case .settings: return "Settings"
        }
    }
}

struct TabBar: View {
    let tabs: [PopoverTab]
    @Binding var active: PopoverTab
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.2))
        )
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func tabButton(_ tab: PopoverTab) -> some View {
        let isActive = (tab == active)
        Button(action: { active = tab }) {
            VStack(spacing: 3) {
                Text(tab.description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isActive ? theme.fg : theme.fgSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                Rectangle()
                    .fill(isActive ? theme.accent : Color.clear)
                    .frame(height: 2)
                    .frame(maxWidth: 24)
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? theme.bgElevHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
