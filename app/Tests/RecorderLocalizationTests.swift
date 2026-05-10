import XCTest
import SwiftUI
@testable import cc_dashboard

/// Loop 32 — guards the `String.localized` extension in
/// `app/Sources/Vendored/KeyboardShortcuts/Utilities.swift`. The vendored
/// `RecorderCocoa.swift` calls `.localized` on string keys at 7 sites; if the
/// dictionary drifts out of sync with the keys, the UI silently falls through
/// to the raw key (e.g. "record_shortcut" instead of "Record Shortcut") which
/// is hard to spot at runtime. These tests pin every key the Recorder uses.
@MainActor
final class RecorderLocalizationTests: XCTestCase {

    // Verifies "record_shortcut" resolves to the upstream English string.
    func testRecordShortcutKey() {
        XCTAssertEqual("record_shortcut".localized, "Record Shortcut")
    }

    // Verifies "press_shortcut" resolves to the upstream English string.
    func testPressShortcutKey() {
        XCTAssertEqual("press_shortcut".localized, "Press Shortcut")
    }

    // Verifies the menu-item conflict format string includes a single `%@` slot.
    func testKeyboardShortcutUsedByMenuItemKey() {
        let value = "keyboard_shortcut_used_by_menu_item".localized
        XCTAssertTrue(value.contains("%@"), "format string must keep %@ for localizedStringWithFormat")
        XCTAssertTrue(value.contains("menu item"), "expected upstream English wording")
    }

    // Verifies the disallowed-shortcut explanation matches upstream.
    func testKeyboardShortcutDisallowedKey() {
        XCTAssertEqual(
            "keyboard_shortcut_disallowed".localized,
            "Option modifier must be combined with Command or Control."
        )
    }

    // Verifies the system-shortcut conflict title.
    func testKeyboardShortcutUsedBySystemKey() {
        XCTAssertEqual(
            "keyboard_shortcut_used_by_system".localized,
            "This keyboard shortcut cannot be used as it’s already a system-wide keyboard shortcut."
        )
    }

    // Verifies the "go to System Settings" follow-up message.
    func testKeyboardShortcutsCanBeChangedKey() {
        let value = "keyboard_shortcuts_can_be_changed".localized
        XCTAssertTrue(value.contains("System Settings"), "expected upstream English wording")
    }

    // Verifies the "OK" button label.
    func testOkKey() {
        XCTAssertEqual("ok".localized, "OK")
    }

    // Verifies the "Use Anyway" button label for the warn conflict policy.
    func testForceUseShortcutKey() {
        XCTAssertEqual("force_use_shortcut".localized, "Use Anyway")
    }

    // Verifies the space-key label (used by Shortcut presentation).
    func testSpaceKey() {
        XCTAssertEqual("space_key".localized, "Space")
    }

    // Verifies unknown keys fall through to `self` so the upstream "missing
    // resource → return key" semantic is preserved.
    func testUnknownKeyFallsThrough() {
        XCTAssertEqual("__not_a_real_key__".localized, "__not_a_real_key__")
    }

    // Verifies that `KeyboardShortcuts.Recorder` is reachable as a SwiftUI
    // View and instantiates without crashing for the two app-defined Names.
    // We can't reliably test rendering in XCTest — just shape-check the type.
    func testRecorderInstantiatesForAppNames() {
        let navigateRecorder = KeyboardShortcuts.Recorder(for: KeyboardShortcuts.Name.navigateMode)
        let quietRecorder = KeyboardShortcuts.Recorder("Toggle Quiet", name: KeyboardShortcuts.Name.toggleQuiet)
        // Erase to AnyView to confirm both are SwiftUI Views and don't trap.
        _ = AnyView(navigateRecorder)
        _ = AnyView(quietRecorder)
    }
}
