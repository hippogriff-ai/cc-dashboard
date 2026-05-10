import XCTest
@testable import cc_dashboard

@MainActor
final class FlashControllerTests: XCTestCase {
    // Verifies a 0 → ≥1 attention-count transition starts flashing.
    func testFlashStartsOnTransitionToAttention() {
        let fc = FlashController()
        XCTAssertFalse(fc.isFlashing)
        fc.update(attentionCount: 0)
        fc.update(attentionCount: 1)
        XCTAssertTrue(fc.isFlashing)
    }

    // Verifies that once stopped, a still-attention count does not re-trigger flashing.
    func testFlashDoesNotRetriggerWhileStillAttention() {
        let fc = FlashController()
        fc.update(attentionCount: 1)
        XCTAssertTrue(fc.isFlashing)
        fc.stopFlashing()                    // user opened popover or quiet
        XCTAssertFalse(fc.isFlashing)
        fc.update(attentionCount: 1)         // same count, no transition
        XCTAssertFalse(fc.isFlashing)
    }

    // Verifies the cap timer auto-stops flashing after `capSeconds` elapse.
    func testFlashAutoCapsAfterCapSeconds() {
        let fc = FlashController(capSeconds: 0.05)
        fc.update(attentionCount: 0)
        fc.update(attentionCount: 1)
        let exp = expectation(description: "auto-stop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertFalse(fc.isFlashing); exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    // Verifies the flash re-arms when attention bumps post-cap (not just on the initial 0→1 transition).
    func testFlashReArmsAfterCap() {
        let fc = FlashController(capSeconds: 0.05)
        fc.update(attentionCount: 1)
        XCTAssertTrue(fc.isFlashing)
        let settled = expectation(description: "cap-settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertFalse(fc.isFlashing)
            XCTAssertTrue(fc.phaseAlert) // settled on alert glyph
            // A new attention bump (1 → 2) post-cap should re-arm the flash.
            fc.update(attentionCount: 2)
            XCTAssertTrue(fc.isFlashing)
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1.0)
    }

    // Verifies a strict-increase update after stopFlashing re-triggers the flash.
    func testStopFlashingThenIncreaseRetriggers() {
        let fc = FlashController()
        fc.update(attentionCount: 1)
        XCTAssertTrue(fc.isFlashing)
        fc.stopFlashing()
        XCTAssertFalse(fc.isFlashing)
        // lastAttentionCount is still 1 after stopFlashing; update(2) is 2>1 && !isFlashing → triggers.
        fc.update(attentionCount: 2)
        XCTAssertTrue(fc.isFlashing)
    }

    // Verifies update(0) clears the baseline so a fresh 0→N transition triggers cleanly.
    func testUpdateZeroClearsBaseline() {
        let fc = FlashController()
        fc.update(attentionCount: 1)
        XCTAssertTrue(fc.isFlashing)
        fc.update(attentionCount: 0)
        XCTAssertFalse(fc.isFlashing)
        fc.update(attentionCount: 1)  // 0 → 1 again, fresh transition
        XCTAssertTrue(fc.isFlashing)
    }

    // Verifies the quiet-mode predicate suppresses flashing entirely.
    func testFlashSuppressedWhenQuiet() {
        let fc = FlashController(isQuiet: { true })
        fc.update(attentionCount: 1)
        XCTAssertFalse(fc.isFlashing)
        // Even a strict-increase doesn't override quiet.
        fc.update(attentionCount: 5)
        XCTAssertFalse(fc.isFlashing)
    }

    // Verifies the onFlashStart hook fires exactly once on a fresh 0 → 1 transition.
    func testNotifyCallbackFiresOnFlashStart() {
        var fired = 0
        let fc = FlashController(onFlashStart: { fired += 1 })
        fc.update(attentionCount: 0)
        fc.update(attentionCount: 1)
        XCTAssertEqual(fired, 1)
    }

    // Verifies quiet mode suppresses the onFlashStart hook (gated by the same predicate as the flash itself).
    func testNotifyCallbackDoesNotFireDuringQuiet() {
        var fired = 0
        let fc = FlashController(
            isQuiet: { true },
            onFlashStart: { fired += 1 }
        )
        fc.update(attentionCount: 0)
        fc.update(attentionCount: 1)
        XCTAssertEqual(fired, 0)
    }

    // Verifies the onFlashStart hook does NOT fire when attention stays at 0.
    func testNotifyCallbackDoesNotFireOnZeroAttention() {
        var fired = 0
        let fc = FlashController(onFlashStart: { fired += 1 })
        fc.update(attentionCount: 0)
        fc.update(attentionCount: 0)
        XCTAssertEqual(fired, 0)
    }

    // Verifies the onFlashStart hook fires again on post-cap re-arm (matches isFlashing transition semantics).
    func testNotifyCallbackFiresOnPostCapReArm() {
        var fired = 0
        let fc = FlashController(capSeconds: 0.05, onFlashStart: { fired += 1 })
        fc.update(attentionCount: 1)
        XCTAssertEqual(fired, 1)
        let settled = expectation(description: "cap-settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Cap has settled; isFlashing == false. A strict-increase bump
            // re-arms startFlashing → fires the hook a second time.
            fc.update(attentionCount: 2)
            XCTAssertEqual(fired, 2)
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1.0)
    }

    // Verifies isEnabled = false suppresses the flash and the onFlashStart hook (Settings toggle gate).
    func testFlashIsSuppressedWhenIsEnabledFalse() {
        var fired = 0
        let fc = FlashController(
            isEnabled: { false },
            onFlashStart: { fired += 1 }
        )
        fc.update(attentionCount: 0)
        fc.update(attentionCount: 1)
        XCTAssertFalse(fc.isFlashing)
        XCTAssertEqual(fired, 0)
    }

    // Verifies an in-flight flash stops if isEnabled flips to false mid-cycle.
    func testInFlightFlashStopsWhenIsEnabledFlipsFalse() {
        var enabled = true
        let fc = FlashController(isEnabled: { enabled })
        fc.update(attentionCount: 1)
        XCTAssertTrue(fc.isFlashing)
        enabled = false
        fc.update(attentionCount: 2)
        XCTAssertFalse(fc.isFlashing)
    }
}
