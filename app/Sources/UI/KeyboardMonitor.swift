// Keyboard monitor for the popover. Owns an `NSEvent.addLocalMonitorForEvents`
// handle that is installed when the popover opens (see `PopoverController`'s
// `popoverDidShow`) and removed when it closes (`popoverDidClose`). The
// monitor returns `nil` for events the resolver consumed and forwards
// everything else (so e.g. typing in a future search field still works).
//
// Pure logic lives in `KeyAction` + `resolveKey(_:navMode:)` so the
// resolver is unit-testable without constructing real `NSEvent`s. The class
// shell is the only thing that actually touches AppKit, and its only job is
// to translate live `NSEvent`s into `KeyInput` values and forward the
// resolved `KeyAction` to a caller-supplied closure.
//
// Task 32 (Loop 32) replaced the prior `registerGlobalHotkeyStub()` no-op
// with a real Carbon hot-key registration owned by `AppDelegate` (it
// subscribes via the vendored `KeyboardShortcuts` module in
// `app/Sources/Vendored/KeyboardShortcuts/`). The popover-local KeyboardMonitor
// only handles in-popover keyboard nav now — global hotkeys live elsewhere.
import AppKit
import os

/// Pure key-input value object so the resolver can be exercised from XCTest
/// without constructing a real `NSEvent` (which requires unsealed APIs and
/// is awkward to mock). The monitor builds one of these from each live
/// `NSEvent.keyDown`, then calls `resolveKey(_:navMode:)`.
struct KeyInput: Equatable {
    /// Hardware-independent key code (`NSEvent.keyCode`).
    let keyCode: UInt16
    /// Lowercased characters string (`NSEvent.charactersIgnoringModifiers`),
    /// already normalised to lowercase so "R" and "r" both map to refresh.
    let characters: String
}

/// Discrete UI intent emitted by the resolver. Names are deliberately
/// abstract — they describe what the user wants, not how it is wired.
/// `PopoverController` translates each case to a concrete state mutation
/// (selection move, tab switch, focus call, etc.).
enum KeyAction: Equatable {
    /// Move selection up one row (↑ / k).
    case up
    /// Move selection down one row (↓ / j).
    case down
    /// Primary action on the focused row (Enter): focus terminal for Live,
    /// push detail / copy resume for Restore.
    case activate
    /// Jump selection to the top row (space). Per UX brief 5.2.
    /// Differs from the task hint that suggested "same as Enter"; the brief
    /// is the more recent design source so we follow it. The task itself
    /// says "pick one and say why" — this is the why.
    case jumpToTop
    /// Cycle to the next tab (Tab). Cycles Live → Restore → Settings →
    /// Live. The UX brief says "Live / Restore"; we cycle all three because
    /// the actual `PopoverTab` enum has three cases and a binary toggle
    /// would skip Settings entirely.
    case switchTab
    /// Force a poll refresh (r). Per UX brief 5.2 ("`r` — force refresh").
    /// The Task 30 brief suggested "toggle navigate mode" as a fallback for
    /// the ambiguous case; the UX brief disambiguates, so we follow it.
    case refresh
    /// Toggle navigate-mode overlay on/off. There is no key bound to this
    /// in the popover-local map (the brief reserves nav-mode for a *global*
    /// hotkey). The action exists so the global-hotkey stub and tests can
    /// drive the same code path the future `KeyboardShortcuts`-vendored
    /// global hotkey will.
    case toggleNavMode
    /// Esc: exit nav-mode if on; otherwise close the popover. The
    /// resolver is stateless, so the `navMode` flag is passed in to
    /// disambiguate the two cases — both arms still emit `.exit`, and the
    /// caller chooses what to do based on its current state.
    case exit
    /// Select the row at this 1-based index (1–9). Only emitted when
    /// `navMode` is true.
    case jumpTo(Int)
}

// MARK: - Pure resolver

/// macOS virtual key codes for the keys we care about. Sourced from
/// `<HIToolbox/Events.h>`; there is no public Swift constant for these in
/// AppKit so we declare them inline rather than import Carbon.
private enum KeyCode {
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let escape: UInt16 = 53
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
    static let enter: UInt16 = 76 // numeric keypad enter
}

/// Pure key resolver. Given a `KeyInput` plus the current `navMode` flag,
/// returns the `KeyAction` to emit, or `nil` to pass the event through
/// unchanged. This function MUST stay free of side effects and free of any
/// AppKit / SwiftUI imports — it is the testable core of the monitor.
func resolveKey(_ input: KeyInput, navMode: Bool) -> KeyAction? {
    // 1) Digits 1–9 — only consumed in nav-mode. We check digits first so
    //    that `1`-on-keyboard still types into a hypothetical text field
    //    when nav-mode is off (resolver returns nil, monitor forwards it).
    if let digit = digitOneToNine(from: input), navMode {
        return .jumpTo(digit)
    }

    // 2) Hardware-keyed actions (arrows / Enter / Tab / space / Esc). We
    //    key off `keyCode` rather than characters because (a) arrows have
    //    no printable characters, (b) Enter and the numeric-keypad Enter
    //    share the .activate behaviour, (c) keyCode is layout-independent.
    switch input.keyCode {
    case KeyCode.upArrow:
        return .up
    case KeyCode.downArrow:
        return .down
    case KeyCode.returnKey, KeyCode.enter:
        return .activate
    case KeyCode.space:
        return .jumpToTop
    case KeyCode.tab:
        return .switchTab
    case KeyCode.escape:
        return .exit
    default:
        break
    }

    // 3) Character-keyed actions (j / k / r). Characters route by string
    //    so non-QWERTY layouts still work — `keyCode` for "j" varies.
    switch input.characters {
    case "j":
        return .down
    case "k":
        return .up
    case "r":
        return .refresh
    default:
        return nil
    }
}

/// Extracts a 1–9 digit from the input's characters, returning nil for
/// any other input. "0" deliberately maps to nil — the spec says 1–9, and
/// 0 has no row to jump to.
private func digitOneToNine(from input: KeyInput) -> Int? {
    guard input.characters.count == 1 else { return nil }
    guard let scalar = input.characters.unicodeScalars.first else { return nil }
    let v = scalar.value
    // ASCII '1' = 49, '9' = 57.
    if v >= 49 && v <= 57 {
        return Int(v) - 48
    }
    return nil
}

// MARK: - Monitor shell

/// Owns the live `NSEvent` local monitor handle. Created once by
/// `PopoverController` and started/stopped on popover show/close.
@MainActor
final class KeyboardMonitor {
    /// Caller-supplied action handler. `PopoverController` wires this to
    /// the actual UI state mutations (selection index, navMode binding,
    /// active tab, focus call). The resolver is pure; this closure is the
    /// only side-effect site.
    var onAction: ((KeyAction) -> Void)?

    /// Snapshot of the current navigate-mode flag. Updated by the caller
    /// (`PopoverController`) whenever the SwiftUI binding flips. Read by
    /// every key event so the resolver can decide whether to consume
    /// digits.
    var navMode: Bool = false

    private var monitorHandle: Any?
    private static let logger = Logger(
        subsystem: "dev.vcheval.cc-dashboard",
        category: "KeyboardMonitor"
    )

    /// Install the local NSEvent monitor. Idempotent: a second `start()`
    /// without an intervening `stop()` is a no-op (and logs).
    func start() {
        if monitorHandle != nil {
            Self.logger.debug("start() called while already running; ignoring")
            return
        }
        let handle = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event: event)
        }
        if handle == nil {
            // `addLocalMonitorForEvents` is documented to return nil on
            // failure; surface that loudly because keyboard nav silently
            // breaking is exactly the silent-failure pattern this codebase
            // forbids.
            Self.logger.error("addLocalMonitorForEvents returned nil; keyboard nav inactive")
            return
        }
        monitorHandle = handle
    }

    /// Remove the local NSEvent monitor. Safe to call when not running.
    func stop() {
        guard let handle = monitorHandle else { return }
        NSEvent.removeMonitor(handle)
        monitorHandle = nil
    }

    deinit {
        // `NSEvent.removeMonitor` is safe to call from any thread, and the
        // handle dealloc would otherwise leak the registered closure for
        // the lifetime of the app. We do NOT log here: deinit may run on a
        // non-main actor under ARC.
        if let handle = monitorHandle {
            NSEvent.removeMonitor(handle)
        }
    }

    /// Translate one live `NSEvent.keyDown` into either a consumed event
    /// (resolver matched → return nil so AppKit drops it) or a passthrough
    /// (resolver did not match → return the original event so the next
    /// responder gets it). Internal so XCTest can call it directly with a
    /// real event when integration coverage is wanted; pure-resolver tests
    /// should target `resolveKey(_:navMode:)` instead.
    private func handle(event: NSEvent) -> NSEvent? {
        let chars = (event.charactersIgnoringModifiers ?? "").lowercased()
        let input = KeyInput(keyCode: event.keyCode, characters: chars)
        guard let action = resolveKey(input, navMode: navMode) else {
            return event
        }
        onAction?(action)
        return nil
    }
}
