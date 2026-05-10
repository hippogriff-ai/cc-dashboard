// Settings tab body for the popover (Task 29). Ports a focused subset of
// docs/ux-design/screens.jsx::SettingsTab (lines 130–270): Appearance (theme
// grid + dark-mode toggle) and Notifications (flash on/off + flash cap
// slider). Hotkeys / Tools / About / Custom mute durations / poll interval
// are deferred to a follow-up loop and represented by a single user-facing
// "More settings will appear here as the app grows." block so the visible UI
// doesn't have a gaping hole.
//
// Theme picker re-renders the popover live: bumping `settings.themeId` /
// `themeMode` triggers `objectWillChange` on the SettingsStore, which causes
// `PopoverPlaceholder` to re-evaluate, which rebuilds `settings.palette` and
// re-injects it via `.environment(\.theme, ...)` inside `PopoverShell`. So
// changing a swatch is end-to-end live without a relaunch.
import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var quietMode: QuietModeStore
    @Environment(\.theme) private var theme
    /// Tracks system-level Notification authorization. Refreshed on appear
    /// so the inline warning under the sound toggle reflects the current
    /// state — e.g. user toggled the System Settings pref while the app
    /// was running. Loop 38.
    @StateObject private var notificationAuth = NotificationAuthStatus()

    private struct ThemeSwatch: Identifiable {
        let id: ThemeId
        let name: String
        let colors: [Color]
    }

    /// Swatch tuples mirror the (bg, accent, fg) triplets used by Themes.swift
    /// so the visual preview lines up with the actual palette the user gets.
    private let swatches: [ThemeSwatch] = [
        ThemeSwatch(id: .claude, name: "Claude", colors: [
            Color(red: 0.110, green: 0.106, blue: 0.098),
            Color(red: 0.852, green: 0.467, blue: 0.341),
            Color(red: 0.961, green: 0.937, blue: 0.902)
        ]),
        ThemeSwatch(id: .tokyoNight, name: "Tokyo Night", colors: [
            Color(red: 0.102, green: 0.106, blue: 0.149),
            Color(red: 0.733, green: 0.604, blue: 0.969),
            Color(red: 0.490, green: 0.812, blue: 1.000)
        ]),
        ThemeSwatch(id: .gruvbox, name: "Gruvbox", colors: [
            Color(red: 0.157, green: 0.157, blue: 0.157),
            Color(red: 0.980, green: 0.741, blue: 0.184),
            Color(red: 0.843, green: 0.600, blue: 0.129)
        ]),
        ThemeSwatch(id: .nord, name: "Nord", colors: [
            Color(red: 0.180, green: 0.204, blue: 0.251),
            Color(red: 0.533, green: 0.753, blue: 0.816),
            Color(red: 0.369, green: 0.506, blue: 0.675)
        ])
    ]

    var body: some View {
        ScrollView { settingsBody }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { notificationAuth.refresh() }
    }

    private var settingsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Appearance")
            themeGrid
            darkModeRow
            sectionHeader("Notifications")
            flashRow
            flashCapRow
            notificationSoundRow
            if notificationAuth.isDenied { notificationAuthDeniedRow }
            sectionHeader("Hotkeys")
            hotkeyRows
            sectionHeader("More")
            comingSoonNote
        }
        .padding(.bottom, 16)
    }

    // MARK: - Sections

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(theme.fgTertiary)
            .textCase(.uppercase)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var themeGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(swatches) { swatch in
                themeSwatchView(swatch)
            }
        }
        .padding(.horizontal, 14)
    }

    private func themeSwatchView(_ swatch: ThemeSwatch) -> some View {
        let isSelected = swatch.id == settings.themeId
        // Three diagonal bands mirroring the JSX gradient (bg 50% / accent 25%
        // / fg 25%). Implemented as a stack of three rectangles clipped by a
        // diagonal mask so the proportions stay stable across grid sizes.
        return Button(action: { settings.themeId = swatch.id }) {
            ZStack(alignment: .bottomLeading) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    ZStack {
                        swatch.colors[0]
                        // Accent band: spans 50%-75% of the diagonal.
                        Rectangle()
                            .fill(swatch.colors[1])
                            .frame(width: w, height: h)
                            .mask(
                                DiagonalBand(start: 0.50, end: 0.75)
                                    .frame(width: w, height: h)
                            )
                        // Foreground band: 75%-100% of diagonal.
                        Rectangle()
                            .fill(swatch.colors[2])
                            .frame(width: w, height: h)
                            .mask(
                                DiagonalBand(start: 0.75, end: 1.0)
                                    .frame(width: w, height: h)
                            )
                    }
                }
                Text(swatch.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                    .padding(.leading, 8)
                    .padding(.bottom, 6)
            }
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? theme.accent : theme.separator,
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var darkModeRow: some View {
        settingRow(label: "Dark mode", sub: nil) {
            ToggleSwitch(
                isOn: Binding(
                    get: { settings.themeMode == .dark },
                    set: { settings.themeMode = $0 ? .dark : .light }
                ),
                accent: theme.accent,
                track: theme.bgElev,
                trackOff: theme.fgQuaternary
            )
        }
    }

    private var flashRow: some View {
        settingRow(label: "Flash on attention",
                   sub: "Status icon blinks when a session needs you") {
            ToggleSwitch(
                isOn: Binding(
                    get: { settings.flashEnabled },
                    set: { settings.flashEnabled = $0 }
                ),
                accent: theme.accent,
                track: theme.bgElev,
                trackOff: theme.fgQuaternary
            )
        }
    }

    private var flashCapRow: some View {
        settingRow(label: "Flash duration cap", sub: nil) {
            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { settings.flashCapSeconds },
                        set: { settings.flashCapSeconds = $0 }
                    ),
                    in: 5...60,
                    step: 1
                )
                .frame(width: 100)
                Text("\(Int(settings.flashCapSeconds))s")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.fgSecondary)
                    .frame(width: 26, alignment: .trailing)
            }
        }
    }

    /// Inline warning shown only when `UNUserNotificationCenter.authorizationStatus
    /// == .denied`. Without this row, toggling "Play sound on attention" while
    /// notifications are denied silently does nothing — a misleading-fallback
    /// pattern. The "Open System Settings" button uses the canonical pane URL
    /// (`x-apple.systempreferences:com.apple.preference.notifications`) so the
    /// user lands directly on the Notifications pane. Loop 38.
    private var notificationAuthDeniedRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(theme.uFailed).frame(width: 6, height: 6).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications denied at the system level")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.fg)
                Text("Toggling \u{201C}Play sound\u{201D} above will have no effect until you re-enable notifications for cc-dashboard in System Settings.")
                    .font(.system(size: 11))
                    .foregroundColor(theme.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(theme.accent)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var notificationSoundRow: some View {
        settingRow(label: "Play sound on attention notification",
                   sub: "Plays the default system sound when a session needs you") {
            ToggleSwitch(
                isOn: Binding(
                    get: { settings.notificationSound },
                    set: { settings.notificationSound = $0 }
                ),
                accent: theme.accent,
                track: theme.bgElev,
                trackOff: theme.fgQuaternary
            )
        }
    }

    /// Hotkey recorder rows. The `KeyboardShortcuts.Recorder` is an
    /// NSViewRepresentable wrapping an NSSearchField; it stores the bound
    /// `KeyboardShortcuts.Name` directly in `UserDefaults`, so AppDelegate's
    /// `wireGlobalShortcuts()` subscription picks up the new shortcut on the
    /// next key event without any manual rebind. Custom label rendering lives
    /// in the row VStack so the text matches the rest of the section's style.
    private var hotkeyRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            hotkeyRow(
                label: "Navigate mode",
                sub: "Toggle navigate mode + open the popover",
                name: .navigateMode
            )
            hotkeyRow(
                label: "Toggle Quiet",
                sub: "Pause attention notifications",
                name: .toggleQuiet
            )
        }
    }

    private func hotkeyRow(label: String, sub: String?, name: KeyboardShortcuts.Name) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.fg)
                if let sub {
                    Text(sub)
                        .font(.system(size: 10.5))
                        .foregroundColor(theme.fgTertiary)
                }
            }
            Spacer(minLength: 8)
            KeyboardShortcuts.Recorder(for: name)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var comingSoonNote: some View {
        Text("More settings will appear here as the app grows.")
            .font(.system(size: 11))
            .foregroundColor(theme.fgTertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Row primitive

    private func settingRow<Trailing: View>(
        label: String,
        sub: String?,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.fg)
                if let sub {
                    Text(sub)
                        .font(.system(size: 10.5))
                        .foregroundColor(theme.fgTertiary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Helpers

/// Toggle pill matching styles.css `.toggle`. SwiftUI's built-in Toggle would
/// render a system control that ignores the popover's themed palette; this
/// hand-rolled version respects the theme.
private struct ToggleSwitch: View {
    @Binding var isOn: Bool
    let accent: Color
    let track: Color
    let trackOff: Color

    var body: some View {
        Button(action: { isOn.toggle() }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? accent.opacity(0.85) : trackOff.opacity(0.5))
                    .frame(width: 30, height: 16)
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .padding(.horizontal, 2)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0.5)
            }
            .frame(width: 30, height: 16)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isOn)
    }
}

/// Diagonal mask shape for the theme swatches. `start` and `end` are unit
/// fractions (0..1) along the diagonal axis (top-left → bottom-right).
private struct DiagonalBand: Shape {
    let start: CGFloat
    let end: CGFloat

    func path(in rect: CGRect) -> Path {
        // Diagonal split lines run perpendicular to a 135-degree gradient
        // (top-left → bottom-right). For a rectangle of size (w, h), a 135deg
        // line at fraction `t` along the diagonal passes through points:
        //   (t * (w + h), 0) and (0, t * (w + h))
        // We clip those to the rect bounds to form the band's polygon.
        let w = rect.width
        let h = rect.height
        let total = w + h
        var p = Path()
        let s = total * start
        let e = total * end

        let p1 = clamped(x: s, y: 0, in: rect)
        let p2 = clamped(x: 0, y: s, in: rect)
        let p3 = clamped(x: 0, y: e, in: rect)
        let p4 = clamped(x: e, y: 0, in: rect)

        p.move(to: p1)
        // Walk along the right/bottom edges between p1 and p4 if they're not
        // collinear (i.e., the band wraps a corner).
        if p1.x >= w || p4.x >= w {
            p.addLine(to: CGPoint(x: w, y: 0))
        }
        p.addLine(to: p4)
        // p4 → p3 along the top edge if p4 is on top.
        if p4.y >= h || p3.y >= h {
            p.addLine(to: CGPoint(x: 0, y: h))
        }
        p.addLine(to: p3)
        p.addLine(to: p2)
        p.closeSubpath()
        return p
    }

    private func clamped(x: CGFloat, y: CGFloat, in rect: CGRect) -> CGPoint {
        let cx = min(max(x, 0), rect.width)
        let cy = min(max(y, 0), rect.height)
        // If the requested point overshoots one axis, project the overshoot
        // onto the other axis along the 135-degree line so the polygon edge
        // hugs the rect corner correctly.
        if x > rect.width {
            return CGPoint(x: rect.width, y: y + (x - rect.width))
        }
        if y > rect.height {
            return CGPoint(x: x + (y - rect.height), y: rect.height)
        }
        return CGPoint(x: cx, y: cy)
    }
}
