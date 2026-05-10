import Foundation
import Combine

/// Two-state attention flasher. State machine:
///   - `update(attentionCount:)`: any strict increase to ≥1 starts flashing
///     (toggles `phaseAlert` every 0.5s) IF not already flashing — so a fresh
///     wave of attention events post-cap correctly re-arms the flash, not just
///     the initial 0 → 1 transition.
///   - `stopFlashing()` (called manually e.g. on popover open or when count
///     drops to 0) clears `isFlashing`, `phaseAlert`, AND `lastAttentionCount`
///     so the next update from any positive count starts a fresh transition.
///   - After `capSeconds` elapses, the cap timer settles on the alert glyph
///     (`phaseAlert = true`, `isFlashing = false`) — still attention-colored,
///     no longer animating. A subsequent attention bump re-arms the flash.
@MainActor
final class FlashController: ObservableObject {
    @Published private(set) var isFlashing: Bool = false
    @Published private(set) var phaseAlert: Bool = false
    private var lastAttentionCount: Int = 0
    private var flashTimer: Timer?
    private var capTimer: Timer?
    private let capSeconds: TimeInterval
    /// Quiet-mode predicate. Default `{ false }` keeps existing tests + call
    /// sites that don't pass a quiet store working unchanged. AppDelegate
    /// wires this to `quietMode.isQuiet` so the flash skips while the user
    /// has the menu-bar muted.
    private let isQuiet: () -> Bool
    /// User preference predicate. `false` means the user has disabled the
    /// flash via the Settings toggle — short-circuits identically to
    /// `isQuiet` (no flash, no `onFlashStart` callback). Default `{ true }`
    /// keeps existing tests + non-UI call sites that don't pass a settings
    /// store working unchanged.
    private let isEnabled: () -> Bool
    /// Side-effect hook fired exactly when a strict-increase transition starts
    /// a fresh flash cycle (i.e. `startFlashing()` is entered). AppDelegate
    /// wires this to post a `UNUserNotificationCenter` notification (Task 33).
    /// Defaults to `nil` so existing tests + non-UI callers don't need to know
    /// about UserNotifications. Crucially the call site lives INSIDE
    /// `startFlashing()`, which `update()` only invokes when (a) not already
    /// flashing AND (b) not in quiet mode AND (c) `isEnabled()` AND
    /// (d) `attentionCount > prev` — so the callback inherits all four gates
    /// without re-checking them.
    private let onFlashStart: (() -> Void)?

    init(
        capSeconds: TimeInterval = 30,
        isQuiet: @escaping () -> Bool = { false },
        isEnabled: @escaping () -> Bool = { true },
        onFlashStart: (() -> Void)? = nil
    ) {
        self.capSeconds = capSeconds
        self.isQuiet = isQuiet
        self.isEnabled = isEnabled
        self.onFlashStart = onFlashStart
    }

    func update(attentionCount: Int) {
        let prev = lastAttentionCount
        lastAttentionCount = attentionCount
        if attentionCount == 0 {
            // No more attention items. Clear flash state. Resetting
            // `lastAttentionCount` to 0 (we just did) means the next positive
            // count reads as a fresh strict-increase transition.
            clearTimersAndFlags()
            return
        }
        // Quiet mode short-circuits. Don't even compare strict-increase — a
        // user who muted the flash shouldn't see it re-arm on the next bump.
        // The flash will re-engage naturally on the next strict-increase that
        // happens AFTER quiet expires (since `lastAttentionCount` is still
        // updated above, we keep accurate baseline either way).
        if isQuiet() {
            // Also stop any in-flight flash if quiet activated mid-cycle.
            if isFlashing { clearTimersAndFlags() }
            return
        }
        if !isEnabled() {
            // User toggled "Flash on attention" off in Settings. Treat
            // identically to quiet mode: kill any in-flight flash, don't
            // post the start callback. Re-engages naturally on the next
            // strict-increase after the toggle flips back on.
            if isFlashing { clearTimersAndFlags() }
            return
        }
        // Re-arm on any strict increase to a positive count, but only when not
        // already flashing — prevents the 0.5s phase timer from being
        // re-instantiated mid-cycle. This rule ALSO covers post-cap re-arm
        // (cap settle leaves isFlashing=false but lastAttentionCount=N; a bump
        // to N+1 satisfies both predicates).
        if attentionCount > prev && !isFlashing {
            startFlashing()
        }
    }

    /// User-initiated dismissal (popover open / Quiet mode). Clears the active
    /// flash but PRESERVES `lastAttentionCount` so an immediate update with the
    /// same count is recognised as "still the same batch, already dismissed"
    /// and does not re-trigger. A strict-increase update post-stop still
    /// re-arms the flash, matching the "fresh attention warrants a fresh
    /// flash" intent.
    func stopFlashing() {
        clearTimersAndFlags()
    }

    private func clearTimersAndFlags() {
        isFlashing = false
        phaseAlert = false
        flashTimer?.invalidate(); flashTimer = nil
        capTimer?.invalidate(); capTimer = nil
    }

    private func startFlashing() {
        isFlashing = true
        phaseAlert = false
        // Fire the start hook synchronously on the same MainActor turn that
        // flips `isFlashing` so observers see a consistent state. Wrapped
        // in a local capture to keep the closure invocation outside the
        // class's published-property setter chain.
        onFlashStart?()

        // Use `Timer(timeInterval:repeats:block:)` + `RunLoop.main.add(forMode: .common)`
        // so the flash continues while the popover/menu is being tracked. The
        // `.scheduledTimer(...)` factory only registers in `.default`, which is
        // dropped during tracking — so the icon would appear to freeze
        // mid-cycle while the user has the popover open.
        let phaseTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Guard against the toggle Task racing with the cap-timer's
                // settle. If we're no longer flashing, don't flip phaseAlert.
                guard self.isFlashing else { return }
                self.phaseAlert.toggle()
            }
        }
        RunLoop.main.add(phaseTimer, forMode: .common)
        flashTimer = phaseTimer

        let cap = Timer(timeInterval: capSeconds, repeats: false) { [weak self] _ in
            // Run synchronously on the main runloop (Timer callbacks already
            // execute there) — no `Task` wrapper. Wrapping in `Task` would let
            // the phase-toggle Task race past the cap settle and flip
            // `phaseAlert` back to false, defeating the cap.
            self?.flashTimer?.invalidate()
            self?.flashTimer = nil
            self?.isFlashing = false
            self?.phaseAlert = true     // settle on alert glyph (still attention-colored, no longer animating)
            self?.capTimer = nil
        }
        RunLoop.main.add(cap, forMode: .common)
        capTimer = cap
    }
}
