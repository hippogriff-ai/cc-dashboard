// Unit tests for the pure `resolveFocusStrategy(session:)` resolver and the
// `FocusStrategy` enum's Equatable conformance. The resolver is a pure
// function with no I/O, so these tests don't need a mock `APIClient` or
// `NSWorkspace` — they construct a `LiveSession` value, call the resolver,
// and assert the returned case.
//
// Note on `LiveSession.sessionId`: the actual `LiveSession` struct in
// `app/Sources/App/APIClient.swift` declares `sessionId` as a non-optional
// `String` (the backend always emits one). The strategy's `sid` parameter
// is `String?` so the call site can grow to accept sid-less inputs (e.g.
// future RecentRepo handoffs) without re-shaping the enum. Tests for the
// nil-sid path therefore exercise the enum case directly rather than going
// through `resolveFocusStrategy`, since the input type can't carry a nil.
import XCTest
@testable import cc_dashboard

final class FocusStrategyTests: XCTestCase {
    /// Builds a minimally-populated `LiveSession`. Every field has a sane
    /// default; callers override only the ones the test cares about. Keeps
    /// the test bodies focused on the behavior under test rather than on
    /// the boilerplate of constructing the struct.
    private func makeSession(cwd: String = "/tmp/r", sessionId: String = "x") -> LiveSession {
        return LiveSession(
            event: .working,
            reason: "",
            priority: 90,
            lastUser: "",
            lastAssistant: "",
            openTool: nil,
            pid: 1,
            sessionId: sessionId,
            cwd: cwd,
            repo: "r",
            branch: nil,
            dirty: 0,
            startedAt: 0,
            lastActivity: 0,
            ageSec: 0,
            staleDecay: 0,
            transcriptFound: true
        )
    }

    /// Canonical v1 path: every `LiveSession` resolves to a `.ghostty`
    /// strategy carrying its cwd + sessionId. This is the only case the
    /// resolver currently constructs; the other enum cases are reserved
    /// for future polyglot sources.
    func testV1AlwaysGhostty() {
        let s = makeSession(cwd: "/tmp/r", sessionId: "x")
        XCTAssertEqual(
            resolveFocusStrategy(session: s),
            .ghostty(cwd: "/tmp/r", sid: "x")
        )
    }

    /// Verifies the `.ghostty` enum case carries `sid: nil` correctly when
    /// constructed with a nil session id. `LiveSession.sessionId` is
    /// non-optional so this exercises the enum directly — the strategy's
    /// optional sid lets the call site grow without re-shaping.
    func testGhosttyCarriesNilSessionId() {
        let strategy: FocusStrategy = .ghostty(cwd: "/tmp/r", sid: nil)
        XCTAssertEqual(strategy, .ghostty(cwd: "/tmp/r", sid: nil))
        XCTAssertNotEqual(strategy, .ghostty(cwd: "/tmp/r", sid: "x"))
    }

    /// Degenerate empty-cwd input still resolves to `.ghostty(cwd: "")`
    /// rather than crashing or returning a different case. The resolver is
    /// pure and does no validation; the empty-cwd policy lives at the API
    /// layer (`APIClient.focus(cwd:sid:)` will produce a non-matching focus
    /// result, which the caller logs). Documenting the contract here so a
    /// future "validate cwd in resolver" change won't silently break the
    /// API-layer assumption.
    func testGhosttyCarriesEmptyCwd() {
        let s = makeSession(cwd: "", sessionId: "x")
        XCTAssertEqual(
            resolveFocusStrategy(session: s),
            .ghostty(cwd: "", sid: "x")
        )
    }

    /// Equatable conformance for the forward-compat cases (`.openWithApp`,
    /// `.openInFinder`) so the dispatcher in `PopoverController` can switch
    /// on them once the polyglot sources land. No resolver path constructs
    /// these in v1; this test guards the enum shape only.
    func testForwardCompatCasesAreEquatable() {
        XCTAssertEqual(
            FocusStrategy.openWithApp(bundleID: "com.example", target: "/tmp/x"),
            FocusStrategy.openWithApp(bundleID: "com.example", target: "/tmp/x")
        )
        XCTAssertEqual(
            FocusStrategy.openInFinder(path: "/tmp/x"),
            FocusStrategy.openInFinder(path: "/tmp/x")
        )
        XCTAssertNotEqual(
            FocusStrategy.openWithApp(bundleID: "com.example", target: "/tmp/x"),
            FocusStrategy.openInFinder(path: "/tmp/x")
        )
    }
}
