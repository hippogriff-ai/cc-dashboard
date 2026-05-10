// Theme system (Tasks 23 + 23.5).
//
// Source-of-truth: docs/ux-design/styles.css `:root` (Claude Dark), with the
// other 3 themes' swatch tuples lifted from docs/ux-design/screens.jsx
// `SettingsTab.themes` (Tokyo Night, Gruvbox, Nord) and rounded out to 16-color
// palettes via `makePalette(bg:accent:fg:)` using the same alpha-on-fg overlay
// pattern that styles.css uses for Claude Dark.
//
// Light variants use canonical light-mode values for each theme family
// (Tokyo Night Day, Gruvbox Light Hard, Nord Snow Storm). Urgency colors stay
// constant across all themes — they're a semantic taxonomy ("color-blind safe"
// per styles.css) and theming them per palette would defeat that property.
import SwiftUI

enum Themes {
    static func palette(for id: ThemeId, mode: ThemeMode) -> ThemePalette {
        switch (id, mode) {
        case (.claude, .dark): return claudeDark
        case (.claude, .light): return claudeLight
        case (.tokyoNight, .dark): return tokyoDark
        case (.tokyoNight, .light): return tokyoLight
        case (.gruvbox, .dark): return gruvboxDark
        case (.gruvbox, .light): return gruvboxLight
        case (.nord, .dark): return nordDark
        case (.nord, .light): return nordLight
        }
    }

    /// Returns true while a (theme × mode) palette is still a stand-in awaiting
    /// real values. After Task 23.5 all 8 palettes are real, so this returns
    /// false — but the affordance is preserved so future themes added in
    /// scaffolding mode can flag themselves via an explicit `case` line.
    /// Settings UI consults this to disable / annotate unimplemented picker rows.
    static func isPlaceholder(_ id: ThemeId, _ mode: ThemeMode) -> Bool {
        return false
    }

    // MARK: - Universal urgency taxonomy
    //
    // Held constant across all themes per styles.css comment
    // "color-blind safe (orange/red/yellow/blue/grey are distinguishable)".
    private static let uPermission = Color(red: 0.91, green: 0.64, blue: 0.24) // amber
    private static let uFailed     = Color(red: 0.85, green: 0.38, blue: 0.33) // red
    private static let uAsk        = Color(red: 0.79, green: 0.56, blue: 0.84) // lavender
    private static let uWorking    = Color(red: 0.44, green: 0.71, blue: 0.85) // cool blue
    private static let uIdle       = Color(red: 0.54, green: 0.61, blue: 0.50) // sage

    /// Derives a full 16-color palette from 3 base RGB tuples + the universal
    /// urgency taxonomy. Mirrors the alpha-on-fg overlay pattern used by
    /// styles.css for Claude Dark, so a freshly-derived palette matches the
    /// design system's tonal hierarchy regardless of theme family.
    private static func makePalette(bg: Color, accent: Color, fg: Color) -> ThemePalette {
        ThemePalette(
            bgWindow: bg.opacity(0.78),
            bgElev: fg.opacity(0.04),
            bgElevHover: fg.opacity(0.07),
            bgRowUrgent: accent.opacity(0.08),
            separator: fg.opacity(0.08),
            fg: fg,
            fgSecondary: fg.opacity(0.62),
            fgTertiary: fg.opacity(0.38),
            fgQuaternary: fg.opacity(0.22),
            accent: accent,
            uPermission: uPermission,
            uFailed: uFailed,
            uAsk: uAsk,
            uWorking: uWorking,
            uIdle: uIdle,
            uClear: fg.opacity(0.32))
    }

    // MARK: - Claude (#1c1b19 / #d97757 / #f5efe6 — styles.css :root)
    //
    // claudeDark is kept as a hand-written literal (NOT routed through
    // makePalette) so it preserves styles.css's specific overlay base
    // (#fff8f0 ≈ Color.white) for bgElev/bgElevHover/separator instead of
    // pulling those from `fg` (#f5efe6). That preserves the existing
    // testClaudeDarkAccentMatchesSpec invariant + matches CSS pixel-for-pixel.

    private static let claudeDark = ThemePalette(
        bgWindow: Color(red: 0.110, green: 0.106, blue: 0.098, opacity: 0.78),
        bgElev: Color.white.opacity(0.04),
        bgElevHover: Color.white.opacity(0.07),
        bgRowUrgent: Color(red: 0.852, green: 0.467, blue: 0.341, opacity: 0.08),
        separator: Color.white.opacity(0.08),
        fg: Color(red: 0.96, green: 0.94, blue: 0.90),
        fgSecondary: Color(red: 0.96, green: 0.94, blue: 0.90, opacity: 0.62),
        fgTertiary: Color(red: 0.96, green: 0.94, blue: 0.90, opacity: 0.38),
        fgQuaternary: Color(red: 0.96, green: 0.94, blue: 0.90, opacity: 0.22),
        accent: Color(red: 0.852, green: 0.467, blue: 0.341),
        uPermission: uPermission,
        uFailed: uFailed,
        uAsk: uAsk,
        uWorking: uWorking,
        uIdle: uIdle,
        uClear: Color(red: 0.96, green: 0.94, blue: 0.90, opacity: 0.32))

    private static let claudeLight = makePalette(
        bg: Color(red: 0.961, green: 0.937, blue: 0.902),    // #f5efe6 cream
        accent: Color(red: 0.852, green: 0.467, blue: 0.341), // #d97757 keep
        fg: Color(red: 0.110, green: 0.106, blue: 0.098))     // #1c1b19 dark

    // MARK: - Tokyo Night (Storm dark / Day light)

    private static let tokyoDark = makePalette(
        bg: Color(red: 0.102, green: 0.106, blue: 0.149),    // #1a1b26
        accent: Color(red: 0.733, green: 0.604, blue: 0.969), // #bb9af7
        fg: Color(red: 0.753, green: 0.792, blue: 0.961))     // #c0caf5

    private static let tokyoLight = makePalette(
        bg: Color(red: 0.882, green: 0.886, blue: 0.906),    // #e1e2e7
        accent: Color(red: 0.596, green: 0.329, blue: 0.945), // #9854f1
        fg: Color(red: 0.216, green: 0.376, blue: 0.749))     // #3760bf

    // MARK: - Gruvbox (Dark Hard / Light Hard)

    private static let gruvboxDark = makePalette(
        bg: Color(red: 0.157, green: 0.157, blue: 0.157),    // #282828
        accent: Color(red: 0.980, green: 0.741, blue: 0.184), // #fabd2f
        fg: Color(red: 0.922, green: 0.859, blue: 0.698))     // #ebdbb2

    private static let gruvboxLight = makePalette(
        bg: Color(red: 0.984, green: 0.945, blue: 0.780),    // #fbf1c7
        accent: Color(red: 0.710, green: 0.463, blue: 0.078), // #b57614
        fg: Color(red: 0.235, green: 0.220, blue: 0.212))     // #3c3836

    // MARK: - Nord (Polar Night dark / Snow Storm light)

    private static let nordDark = makePalette(
        bg: Color(red: 0.180, green: 0.204, blue: 0.251),    // #2e3440
        accent: Color(red: 0.533, green: 0.753, blue: 0.816), // #88c0d0
        fg: Color(red: 0.925, green: 0.937, blue: 0.957))     // #eceff4

    private static let nordLight = makePalette(
        bg: Color(red: 0.925, green: 0.937, blue: 0.957),    // #eceff4
        accent: Color(red: 0.369, green: 0.506, blue: 0.675), // #5e81ac
        fg: Color(red: 0.180, green: 0.204, blue: 0.251))     // #2e3440
}

// Inject palette via environment.
private struct ThemeKey: EnvironmentKey {
    static let defaultValue: ThemePalette = Themes.palette(for: .claude, mode: .dark)
}

extension EnvironmentValues {
    var theme: ThemePalette {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
