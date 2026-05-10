// Popover outer chrome. Provides the warm-tinted dark window background
// (NSVisualEffectView blur + theme.bgWindow tint overlay) and the rounded-
// rectangle clip from styles.css `.popover` (`--radius-popover: 14px`).
//
// As of Task 28, sizing is driven by the inner content (PopoverPlaceholder
// resizes itself between 560pt and 620pt depending on whether
// `selectedDetail` is non-nil). PopoverShell is now a pure chrome wrapper —
// its content provides its own frame.
import SwiftUI
import AppKit

struct PopoverShell<Content: View>: View {
    /// Optional explicit palette. When provided, this shell injects it into
    /// the SwiftUI environment so all child views see the live theme. When
    /// `nil`, the shell falls back to whatever palette is already on the
    /// environment (preserving older call sites that don't pass one).
    var palette: ThemePalette?
    @Environment(\.theme) private var ambientTheme
    @ViewBuilder var content: () -> Content

    init(palette: ThemePalette? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.palette = palette
        self.content = content
    }

    var body: some View {
        let active = palette ?? ambientTheme
        return VStack(spacing: 0) { content() }
            .background(
                ZStack {
                    VisualEffect()
                    active.bgWindow
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .environment(\.theme, active)
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .menu
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
