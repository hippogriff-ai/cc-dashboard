// Transient toast banner shown at the top of the popover content stack
// (Loop 34). Renders nothing when `error == nil`; otherwise renders a
// horizontal pill with a single-line message + close button. Tap-anywhere
// dismisses; the X glyph is purely a visual affordance.
//
// Color comes from the active theme: `.error` uses `theme.uFailed`, `.warning`
// uses `theme.uPermission`, `.info` uses `theme.bgElevHover`. The palette
// doesn't expose dedicated `danger`/`warning` tokens (only an urgency
// taxonomy), so we reuse `uFailed` / `uPermission` here — they're the same
// semantic shade the urgency dots use, which keeps the banner visually
// coherent with the rest of the popover.
//
// Auto-dismiss is owned by `PopoverViewModel.showError`; this view is purely
// presentational. The `dismiss` closure exists so a tap or X-click can clear
// the error before the timer fires.
import SwiftUI

struct ErrorBanner: View {
    let error: PopoverError?
    let dismiss: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let error {
                HStack(spacing: 8) {
                    Text(error.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.fg)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(theme.fgSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss error")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor(for: error.kind))
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: error?.id)
    }

    private func backgroundColor(for kind: PopoverError.Kind) -> Color {
        switch kind {
        case .error:
            return theme.uFailed.opacity(0.85)
        case .warning:
            return theme.uPermission.opacity(0.85)
        case .info:
            return theme.bgElevHover
        }
    }
}
