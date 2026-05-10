// Quiet mode (Task 29). When `isQuiet` is true, FlashController suppresses
// the menu-bar flash. State persists across launches via `UserDefaults` so
// "mute until tomorrow 9 AM" survives a relaunch.
//
// Storage encoding: `Date.timeIntervalSince1970` (Double) under
// `quietUntil`. Absent / NaN / past values all read back as "not quiet".
import Foundation
import SwiftUI
import os

@MainActor
final class QuietModeStore: ObservableObject {
    @Published private(set) var quietUntil: Date?

    private let defaults: UserDefaults
    private static let key = "quietUntil"
    private static let logger = Logger(subsystem: "dev.vcheval.cc-dashboard", category: "QuietModeStore")

    /// Decay timer that fires when `quietUntil` is reached, clearing the
    /// `isQuiet` state and triggering UI re-render. Without this the QuietPill
    /// would visually claim "Quiet" until some unrelated state change forced a
    /// re-render.
    private var decayTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.key) != nil {
            let ts = defaults.double(forKey: Self.key)
            if ts.isFinite && ts > 0 {
                let date = Date(timeIntervalSince1970: ts)
                if date > Date() {
                    self.quietUntil = date
                    scheduleDecay(at: date)
                } else {
                    defaults.removeObject(forKey: Self.key)
                    self.quietUntil = nil
                }
            } else {
                Self.logger.error("corrupt stored quietUntil ts=\(ts, privacy: .public); wiping key")
                defaults.removeObject(forKey: Self.key)
                self.quietUntil = nil
            }
        } else {
            self.quietUntil = nil
        }
    }

    deinit {
        decayTimer?.invalidate()
    }

    private func scheduleDecay(at date: Date) {
        decayTimer?.invalidate()
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            // Decay synchronously on the main runloop. Even if the user has
            // already manually unmuted (quietUntil = nil) the unmute() call
            // below is idempotent.
            Task { @MainActor in self?.unmute() }
        }
        RunLoop.main.add(t, forMode: .common)
        decayTimer = t
    }

    var isQuiet: Bool {
        guard let until = quietUntil else { return false }
        return until > Date()
    }

    func mute(for interval: TimeInterval) {
        mute(until: Date().addingTimeInterval(interval))
    }

    func mute(until date: Date) {
        quietUntil = date
        defaults.set(date.timeIntervalSince1970, forKey: Self.key)
        scheduleDecay(at: date)
    }

    func unmute() {
        quietUntil = nil
        defaults.removeObject(forKey: Self.key)
        decayTimer?.invalidate()
        decayTimer = nil
    }

    /// One-tap toggle bound to the header `QuietPill`. Defaults to a 1-hour
    /// mute window, matching the screens.jsx affordance.
    func toggle() {
        if isQuiet {
            unmute()
        } else {
            mute(for: 60 * 60)
        }
    }
}
