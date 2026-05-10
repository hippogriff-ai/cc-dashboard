// Named global hotkey declarations (Task 32). The actual subscription is set
// up in `AppDelegate.applicationDidFinishLaunching` — this file only declares
// the strongly-typed names so that test code and AppDelegate can refer to the
// same identifiers.
//
// Default-shortcut policy:
//   - `.toggleQuiet` ships with a default of ⌃⌥M, matching plan Step 4.
//   - `.navigateMode` ships with NO default. Configurable in code only until
//     the Recorder UI lands in SettingsView (deferred from this loop).
//
// `KeyboardShortcuts.Name`'s `init(_:initial:)` registers the initial shortcut
// in `UserDefaults` on first construction. After that the user (or future
// Recorder UI) is the source of truth — re-running this declaration with a
// different default does NOT clobber a user override (upstream documents this
// as the "annoying random-app-stealing-shortcuts" pitfall it avoids).
import Foundation

extension KeyboardShortcuts.Name {
    /// Toggle navigate mode + open the popover if hidden. No default — the
    /// global hotkey is opt-in via the Recorder UI (deferred). Until then,
    /// this Name has no shortcut and the closure registered in AppDelegate
    /// will simply never fire.
    static let navigateMode = Self("navigateMode")

    /// Toggle Quiet mode. Default: ⌃⌥M (control + option + M). The default is
    /// only applied on first launch — subsequent runs honor any user override.
    static let toggleQuiet = Self("toggleQuiet", initial: .init(.m, modifiers: [.control, .option]))
}
