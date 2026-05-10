import XCTest
@testable import cc_dashboard

/// Pure-resolver tests for `resolveKey(_:navMode:)`. We deliberately do
/// NOT exercise the live `NSEvent` monitor — Step 4 of Task 30 says the
/// visual / live-monitor coverage is manual. Constructing real
/// `NSEvent.keyDown` events from XCTest is awkward (private SPI) and the
/// pure resolver carries the entire decision logic, so unit-testing the
/// resolver gives us all the coverage that matters.
final class KeyboardMonitorTests: XCTestCase {

    // MARK: - Helpers

    /// Build a `KeyInput` with characters defaulting to empty so tests
    /// that key purely off `keyCode` (arrows, Enter, Tab, Esc, space)
    /// don't have to repeat themselves.
    private func input(keyCode: UInt16, characters: String = "") -> KeyInput {
        KeyInput(keyCode: keyCode, characters: characters)
    }

    // MARK: - Arrow keys

    // Verifies up-arrow (keyCode 126) resolves to .up.
    func testUpArrowResolvesToUp() {
        let action = resolveKey(input(keyCode: 126), navMode: false)
        XCTAssertEqual(action, .up)
    }

    // Verifies down-arrow (keyCode 125) resolves to .down.
    func testDownArrowResolvesToDown() {
        let action = resolveKey(input(keyCode: 125), navMode: false)
        XCTAssertEqual(action, .down)
    }

    // MARK: - Vim keys

    // Verifies "j" character resolves to .down (vim alias for ↓).
    func testJResolvesToDown() {
        // keyCode is irrelevant for character-keyed actions; pass an
        // unrelated value so we know the test exercises the character arm.
        let action = resolveKey(input(keyCode: 38, characters: "j"), navMode: false)
        XCTAssertEqual(action, .down)
    }

    // Verifies "k" character resolves to .up (vim alias for ↑).
    func testKResolvesToUp() {
        let action = resolveKey(input(keyCode: 40, characters: "k"), navMode: false)
        XCTAssertEqual(action, .up)
    }

    // MARK: - Activation / tab / refresh / exit

    // Verifies Return (keyCode 36) resolves to .activate.
    func testReturnResolvesToActivate() {
        let action = resolveKey(input(keyCode: 36), navMode: false)
        XCTAssertEqual(action, .activate)
    }

    // Verifies numeric-keypad Enter (keyCode 76) also resolves to .activate.
    func testKeypadEnterResolvesToActivate() {
        let action = resolveKey(input(keyCode: 76), navMode: false)
        XCTAssertEqual(action, .activate)
    }

    // Verifies space (keyCode 49) resolves to .jumpToTop per UX brief 5.2.
    func testSpaceResolvesToJumpToTop() {
        let action = resolveKey(input(keyCode: 49), navMode: false)
        XCTAssertEqual(action, .jumpToTop)
    }

    // Verifies Tab (keyCode 48) resolves to .switchTab.
    func testTabResolvesToSwitchTab() {
        let action = resolveKey(input(keyCode: 48), navMode: false)
        XCTAssertEqual(action, .switchTab)
    }

    // Verifies "r" character resolves to .refresh (UX brief 5.2: force refresh).
    func testRResolvesToRefresh() {
        let action = resolveKey(input(keyCode: 15, characters: "r"), navMode: false)
        XCTAssertEqual(action, .refresh)
    }

    // Verifies Escape (keyCode 53) resolves to .exit.
    func testEscapeResolvesToExit() {
        let action = resolveKey(input(keyCode: 53), navMode: false)
        XCTAssertEqual(action, .exit)
    }

    // Verifies Escape resolves to .exit even when navMode is on (caller
    // distinguishes "exit nav" vs "close popover" itself; resolver stays pure).
    func testEscapeResolvesToExitWhenNavModeOn() {
        let action = resolveKey(input(keyCode: 53), navMode: true)
        XCTAssertEqual(action, .exit)
    }

    // MARK: - Digits with nav-mode on

    // Verifies "1"–"9" each map to .jumpTo(n) when navMode is true.
    func testDigitsWhenNavModeOnEmitJumpTo() {
        for n in 1...9 {
            let action = resolveKey(
                input(keyCode: 0, characters: String(n)),
                navMode: true
            )
            XCTAssertEqual(action, .jumpTo(n), "digit \(n) should produce .jumpTo(\(n))")
        }
    }

    // Verifies "0" with navMode on does NOT emit .jumpTo (spec is 1–9 only).
    func testZeroWithNavModeOnIsIgnored() {
        let action = resolveKey(input(keyCode: 0, characters: "0"), navMode: true)
        XCTAssertNil(action)
    }

    // MARK: - Digits with nav-mode off

    // Verifies "1" with navMode off returns nil (digits only fire when nav-mode is active).
    func testDigitOneWithNavModeOffIsNil() {
        let action = resolveKey(input(keyCode: 0, characters: "1"), navMode: false)
        XCTAssertNil(action)
    }

    // Verifies "9" with navMode off returns nil — same rule, opposite end of the range.
    func testDigitNineWithNavModeOffIsNil() {
        let action = resolveKey(input(keyCode: 0, characters: "9"), navMode: false)
        XCTAssertNil(action)
    }

    // MARK: - Unknown keys

    // Verifies an unknown letter (e.g. "z") resolves to nil.
    func testUnknownLetterResolvesToNil() {
        let action = resolveKey(input(keyCode: 6, characters: "z"), navMode: false)
        XCTAssertNil(action)
    }

    // Verifies an unknown keyCode with empty characters resolves to nil.
    func testUnknownKeyCodeResolvesToNil() {
        let action = resolveKey(input(keyCode: 200), navMode: false)
        XCTAssertNil(action)
    }

    // MARK: - Case folding

    // Verifies that the resolver expects already-lowercased characters
    // (the live monitor lowercases before calling). Documents the contract.
    func testUpperCaseRDoesNotResolve() {
        // Resolver requires lowercase input — the live monitor normalises
        // before calling. Documents the contract: callers MUST lowercase.
        let action = resolveKey(input(keyCode: 15, characters: "R"), navMode: false)
        XCTAssertNil(action)
    }
}
