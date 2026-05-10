// User-visible app preferences (Task 29). Persisted via `UserDefaults`.
//
// Why direct `UserDefaults` reads (not `@AppStorage`)? `@AppStorage` is a
// SwiftUI property wrapper that requires a `View` host to publish changes via
// the SwiftUI environment. Inside an `ObservableObject` class we'd lose the
// publish path unless we re-emit `objectWillChange` ourselves — at which point
// the `@AppStorage` wrapper is just bookkeeping that a plain
// `UserDefaults.standard` round-trip already handles. So we keep this class
// boilerplate-explicit: each setter writes through to defaults AND fires
// `objectWillChange.send()` so SwiftUI views observing the store re-render.
//
// Defensive enum decoding: `ThemeId(rawValue:) ?? .claude` (and the equivalent
// for `ThemeMode`) so a forward-compat string change in stored defaults
// doesn't soft-brick the popover.
import Foundation
import SwiftUI
import os

@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private static let logger = Logger(subsystem: "dev.vcheval.cc-dashboard", category: "SettingsStore")

    /// Slider clamp range for `flashCapSeconds`. Same range as the SettingsView
    /// slider; enforced at the storage layer so a hand-edited plist with -50 or
    /// 600 doesn't propagate into a Timer that fires immediately or every 10
    /// minutes. Reasonable upper bound: longer than 60s and the user might
    /// think the icon is broken.
    private static let flashCapMin: Double = 5
    private static let flashCapMax: Double = 60
    private static let flashCapDefault: Double = 30

    private enum Key {
        static let themeId = "themeId"
        static let themeMode = "themeMode"
        static let flashEnabled = "flashEnabled"
        static let flashCapSeconds = "flashCapSeconds"
        static let notificationSound = "notificationSound"
        static let notificationDenialAcknowledged = "notificationDenialAcknowledged"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var themeId: ThemeId {
        get {
            guard let raw = defaults.string(forKey: Key.themeId) else { return .claude }
            if let id = ThemeId(rawValue: raw) { return id }
            // Stored value doesn't decode — schema migration, manual edit, or
            // forward-compat reset. Log so the regression is visible in
            // Console.app rather than silently snapping back to Claude.
            Self.logger.error("invalid stored themeId=\(raw, privacy: .public); falling back to .claude")
            return .claude
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: Key.themeId)
        }
    }

    var themeMode: ThemeMode {
        get {
            guard let raw = defaults.string(forKey: Key.themeMode) else { return .dark }
            if let mode = ThemeMode(rawValue: raw) { return mode }
            Self.logger.error("invalid stored themeMode=\(raw, privacy: .public); falling back to .dark")
            return .dark
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: Key.themeMode)
        }
    }

    var flashEnabled: Bool {
        get {
            // Default to true when the key is absent (first launch) — match the
            // documented out-of-box "flash on attention" behaviour. Using
            // `object(forKey:)` to distinguish "absent" from "explicitly false".
            if defaults.object(forKey: Key.flashEnabled) == nil { return true }
            return defaults.bool(forKey: Key.flashEnabled)
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.flashEnabled)
        }
    }

    var flashCapSeconds: Double {
        get {
            if defaults.object(forKey: Key.flashCapSeconds) == nil {
                return Self.flashCapDefault
            }
            let raw = defaults.double(forKey: Key.flashCapSeconds)
            // Clamp + finite-check on read so a corrupt or out-of-range stored
            // value can't drive a Timer with NaN / negative interval.
            guard raw.isFinite, raw >= Self.flashCapMin, raw <= Self.flashCapMax else {
                Self.logger.error("invalid stored flashCapSeconds=\(raw, privacy: .public); falling back to default")
                return Self.flashCapDefault
            }
            return raw
        }
        set {
            objectWillChange.send()
            let clamped = max(Self.flashCapMin, min(Self.flashCapMax, newValue.isFinite ? newValue : Self.flashCapDefault))
            defaults.set(clamped, forKey: Key.flashCapSeconds)
        }
    }

    /// Whether the OS notification posted on attention transitions (Task 33)
    /// plays the default system sound. Default is `true` — user can mute via
    /// the Notifications section in SettingsView. Independent of `flashEnabled`
    /// so a user who wants the menu-bar flash without an audible ping can have
    /// it (and vice versa).
    var notificationSound: Bool {
        get {
            if defaults.object(forKey: Key.notificationSound) == nil { return true }
            return defaults.bool(forKey: Key.notificationSound)
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.notificationSound)
        }
    }

    /// Set to `true` once the user has been shown the "notifications denied —
    /// enable in System Settings" banner (Loop 34). Without this flag the
    /// banner would re-fire on every launch since `requestAuthorization` is
    /// called unconditionally in `applicationDidFinishLaunching`. Stored via
    /// the same absent-vs-explicit `object(forKey:)` pattern as
    /// `flashEnabled` so a user who manually un-acknowledges via defaults
    /// can replay the banner.
    var notificationDenialAcknowledged: Bool {
        get {
            if defaults.object(forKey: Key.notificationDenialAcknowledged) == nil { return false }
            return defaults.bool(forKey: Key.notificationDenialAcknowledged)
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.notificationDenialAcknowledged)
        }
    }

    /// Computed palette derived from the currently-selected (themeId, themeMode).
    /// Re-reads on every access — cheap (table lookup) and guarantees freshness
    /// after a setter mutation.
    var palette: ThemePalette { Themes.palette(for: themeId, mode: themeMode) }
}
