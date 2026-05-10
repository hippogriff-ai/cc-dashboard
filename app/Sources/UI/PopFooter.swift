// Popover footer: gear + refresh icon-buttons on the left, kbd-hint text on
// the right. Ports docs/ux-design/components.jsx `PopFooter` / styles.css
// `.pop-footer` and `.kbd-hint`.
import SwiftUI

struct PopFooter: View {
    var hint: String? = nil
    var onSettings: () -> Void = {}
    var onRefresh: () -> Void = {}
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            HStack(spacing: 2) {
                IconButton(name: .gear, action: onSettings)
                IconButton(name: .refresh, action: onRefresh)
            }
            Spacer()
            kbdHint
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.separator)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var kbdHint: some View {
        if let hint {
            Text(hint)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(theme.fgTertiary)
        } else {
            HStack(spacing: 2) {
                kbdKey("↑↓")
                Text("nav").font(.system(size: 10.5, design: .monospaced)).foregroundColor(theme.fgTertiary)
                kbdKey("⏎")
                Text("open").font(.system(size: 10.5, design: .monospaced)).foregroundColor(theme.fgTertiary)
                kbdKey("⇥")
                Text("tab").font(.system(size: 10.5, design: .monospaced)).foregroundColor(theme.fgTertiary)
            }
        }
    }

    @ViewBuilder
    private func kbdKey(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(theme.fgQuaternary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.bgElev)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(theme.separator, lineWidth: 1)
            )
    }
}

private struct IconButton: View {
    let name: IconName
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Icon(name: name, size: 14, tint: theme.fgSecondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovered ? theme.bgElevHover : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
