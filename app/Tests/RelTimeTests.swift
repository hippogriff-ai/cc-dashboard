// Unit tests for `RelTime.format(_:now:)` and `RelTime.isStale(_:now:thresholdSec:)`.
// Both helpers take an injectable `now: Date` so tests pin a deterministic
// reference time (`Date(timeIntervalSince1970: 1_000_000)` here) and compute
// `msEpoch` as offsets relative to that reference. This avoids any reliance
// on wall-clock time during the test run.
import XCTest
@testable import cc_dashboard

final class RelTimeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    /// Reference time expressed in milliseconds since the Unix epoch — the
    /// units `RelTime.format` and `RelTime.isStale` expect for `msEpoch`.
    private var nowMs: Double { now.timeIntervalSince1970 * 1000 }

    /// 0-second offset → "now" (anything <5s collapses to the literal label).
    func testFormatNowZeroSeconds() {
        XCTAssertEqual(RelTime.format(nowMs, now: now), "now")
    }

    /// 30-second offset → "30s ago" (sub-minute path).
    func testFormatThirtySeconds() {
        XCTAssertEqual(RelTime.format(nowMs - 30 * 1000, now: now), "30s ago")
    }

    /// 5-minute offset → "5m ago" (sub-hour path).
    func testFormatFiveMinutes() {
        XCTAssertEqual(RelTime.format(nowMs - 5 * 60 * 1000, now: now), "5m ago")
    }

    /// 2-hour offset → "2h ago" (sub-day path).
    func testFormatTwoHours() {
        XCTAssertEqual(RelTime.format(nowMs - 2 * 60 * 60 * 1000, now: now), "2h ago")
    }

    /// 3-day offset → "3d ago" (multi-day path).
    func testFormatThreeDays() {
        XCTAssertEqual(RelTime.format(nowMs - 3 * 24 * 60 * 60 * 1000, now: now), "3d ago")
    }

    /// At the threshold (exactly 30min ago) `isStale` is false; one second
    /// older flips it true. Boundary check guards against future off-by-one
    /// regressions if the comparison operator changes.
    func testIsStaleBoundary() {
        let thirtyMinMs = 30.0 * 60.0 * 1000.0
        XCTAssertFalse(RelTime.isStale(nowMs - thirtyMinMs, now: now))
        XCTAssertTrue(RelTime.isStale(nowMs - thirtyMinMs - 1000, now: now))
    }

    /// `msEpoch == 0` (uninitialized backend payload) renders the em-dash
    /// sentinel rather than "20597d ago". Same path for any negative value.
    func testFormatEpochZeroReturnsSentinel() {
        XCTAssertEqual(RelTime.format(0, now: now), "—")
        XCTAssertEqual(RelTime.format(-1, now: now), "—")
    }

    /// Backend timestamp slightly in the future (clock skew) collapses to
    /// "now" rather than "-30s ago" — preserves the no-information signal
    /// without producing a meaningless negative duration.
    func testFormatFutureTimestampCollapsesToNow() {
        XCTAssertEqual(RelTime.format(nowMs + 30 * 1000, now: now), "now")
    }
}
