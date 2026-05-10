import SwiftUI
import AppKit
import os

/// Owns the menu-bar `NSStatusItem`'s image. Polls the attached `PollingStore`
/// every 2s on the main run loop in `.common` modes (so it keeps firing while
/// the menu/popover is being tracked — same pattern as `PollingStore` itself).
/// Drives `FlashController` from `store.attentionCount` and reflects
/// `flash.phaseAlert` onto the status item button's image.
@MainActor
final class StatusIconController {
    private let item: NSStatusItem
    private let flash: FlashController
    private weak var store: PollingStore?
    private var refreshTimer: Timer?

    private static let logger = Logger(subsystem: "dev.vcheval.cc-dashboard", category: "StatusIcon")

    init(item: NSStatusItem, flash: FlashController, store: PollingStore) {
        self.item = item
        self.flash = flash
        self.store = store
        item.button?.image = Self.iconBaseline()

        // Schedule on the main run loop in `.common` modes so the icon keeps
        // refreshing while a menu/popover is being tracked. Storing the timer
        // means we can invalidate it in `deinit` and avoid orphaned ticks
        // after the controller is replaced (e.g. on backend respawn).
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }

    deinit {
        // `Timer.invalidate()` is documented thread-safe; calling it from a
        // potentially non-main dealloc is fine and prevents the run loop from
        // retaining a fired-but-stale closure past our lifetime.
        refreshTimer?.invalidate()
    }

    func refresh() {
        guard let store else { return }
        let count = store.attentionCount
        flash.update(attentionCount: count)
        let alert = flash.phaseAlert
        item.button?.image = alert ? Self.iconAlert() : Self.iconBaseline()
    }

    private static func iconBaseline() -> NSImage {
        if let img = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "cc-dashboard") {
            img.isTemplate = true
            return img
        }
        logger.warning("SF Symbol 'square.stack.3d.up.fill' unavailable; using drawn fallback")
        return drawnFallback(accessibility: "cc-dashboard")
    }

    /// Alert glyph rendered in `systemRed` so the menu bar shows it literally
    /// (instead of re-tinting to the menu bar's foreground color). The flash
    /// animation toggles between this and the baseline every 0.5s, so the
    /// user sees a strong red ↔ template blink rather than a same-color
    /// shape-only swap. After `FlashController.capSeconds` (30s default)
    /// the flash settles on this image steady — still visibly red — so the
    /// signal persists for sessions the user takes a while to reach. Loop 39.
    private static func iconAlert() -> NSImage {
        guard let base = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "attention") else {
            logger.warning("SF Symbol 'exclamationmark.triangle.fill' unavailable; using drawn fallback")
            return drawnFallback(accessibility: "attention", color: .systemRed)
        }
        // `paletteColors` overrides the symbol's default tint at render time.
        // `isTemplate = false` is the critical bit: template images are
        // re-tinted by AppKit to match the system menu bar foreground color,
        // which erases the red. Setting it false makes the menu bar render
        // the literal pixel colors.
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
        if let colored = base.withSymbolConfiguration(config) {
            colored.isTemplate = false
            colored.accessibilityDescription = "attention"
            return colored
        }
        // withSymbolConfiguration returns nil only if the SF Symbols bridge
        // can't apply the config (e.g. exotic symbol variants). Fall back to
        // the manual drawn red triangle so the alert never silently fails to
        // catch the eye.
        return drawnFallback(accessibility: "attention", color: .systemRed)
    }

    /// 16x16 filled-rect (or red triangle for alert) drawn on demand. Called
    /// only on the SF-Symbols-unavailable fallback path. When `color` is nil
    /// the result is a template image (system-tinted); when set, the result
    /// is a literal-colored image. The alert variant is non-template + red
    /// so the menu bar surface still gets a strongly-colored fallback.
    private static func drawnFallback(accessibility: String, color: NSColor? = nil) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            (color ?? .black).setFill()
            rect.insetBy(dx: 2, dy: 2).fill()
            return true
        }
        img.isTemplate = (color == nil)
        img.accessibilityDescription = accessibility
        return img
    }
}
