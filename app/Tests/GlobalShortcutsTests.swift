import XCTest
@testable import cc_dashboard

/// Declarative checks on the global-hotkey Name registry (Task 32). We do
/// NOT test live Carbon registration — that requires a running event loop
/// and CGEvent injection, which is manual smoke-test territory.
@MainActor
final class GlobalShortcutsTests: XCTestCase {

    // Verifies that `.toggleQuiet` ships with the default control + option + M shortcut.
    func testToggleQuietHasDefaultShortcut() {
        let name = KeyboardShortcuts.Name.toggleQuiet
        guard let initial = name.initialShortcut else {
            XCTFail("toggleQuiet should ship with an initial shortcut")
            return
        }
        XCTAssertEqual(initial.key, .m)
        XCTAssertTrue(initial.modifiers.contains(.control))
        XCTAssertTrue(initial.modifiers.contains(.option))
        // Ensure no extra modifiers crept in (would change the published binding).
        XCTAssertFalse(initial.modifiers.contains(.command))
        XCTAssertFalse(initial.modifiers.contains(.shift))
    }

    // Verifies that `.navigateMode` ships with NO default — Recorder UI is deferred.
    func testNavigateModeHasNoDefaultShortcut() {
        let name = KeyboardShortcuts.Name.navigateMode
        XCTAssertNil(name.initialShortcut, "navigateMode should not ship with a default shortcut until the Recorder UI lands")
    }

    // Verifies the Name rawValues match the strings used by UserDefaults storage.
    func testNamesUseExpectedRawValues() {
        XCTAssertEqual(KeyboardShortcuts.Name.toggleQuiet.rawValue, "toggleQuiet")
        XCTAssertEqual(KeyboardShortcuts.Name.navigateMode.rawValue, "navigateMode")
    }
}
