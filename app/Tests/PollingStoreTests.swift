import XCTest
@testable import cc_dashboard

final class PollingStoreTests: XCTestCase {
    // Verifies sort() ranks by priority ascending first, then lastActivity descending within ties.
    func testSortRanksByPriorityThenActivity() {
        let s1 = LiveSession(
            event: .working,
            reason: "",
            priority: 90,
            lastUser: "",
            lastAssistant: "",
            openTool: nil,
            pid: 1,
            sessionId: "a",
            cwd: "/x",
            repo: "x",
            branch: nil,
            dirty: 0,
            startedAt: 0,
            lastActivity: 100,
            ageSec: 0,
            staleDecay: 0,
            transcriptFound: true
        )
        let s2 = LiveSession(
            event: .permissionPending,
            reason: "",
            priority: 5,
            lastUser: "",
            lastAssistant: "",
            openTool: nil,
            pid: 2,
            sessionId: "b",
            cwd: "/y",
            repo: "y",
            branch: nil,
            dirty: 0,
            startedAt: 0,
            lastActivity: 200,
            ageSec: 0,
            staleDecay: 0,
            transcriptFound: true
        )
        let sorted = PollingStore.sort([s1, s2])
        XCTAssertEqual(sorted.first?.sessionId, "b")
    }

    // Verifies attentionCount(of:) counts only permission/ask/failed events and ignores working/idle.
    func testAttentionCount() {
        let permission = makeSession(sessionId: "p", event: .permissionPending, priority: 5)
        let toolFailed = makeSession(sessionId: "f", event: .toolFailed, priority: 10)
        let ask = makeSession(sessionId: "a", event: .ask, priority: 20)
        let working = makeSession(sessionId: "w", event: .working, priority: 50)
        let idle = makeSession(sessionId: "i", event: .idleAfterComplete, priority: 80)

        let count = PollingStore.attentionCount(of: [permission, toolFailed, ask, working, idle])
        XCTAssertEqual(count, 3)
    }

    // Verifies attentionCount(of:) returns 0 for an empty array (boundary).
    func testAttentionCountEmpty() {
        XCTAssertEqual(PollingStore.attentionCount(of: []), 0)
    }

    // MARK: - Fixture helpers

    private func makeSession(
        sessionId: String,
        event: SessionEvent,
        priority: Int,
        lastActivity: Double = 0
    ) -> LiveSession {
        LiveSession(
            event: event,
            reason: "",
            priority: priority,
            lastUser: "",
            lastAssistant: "",
            openTool: nil,
            pid: 1,
            sessionId: sessionId,
            cwd: "/tmp",
            repo: "tmp",
            branch: nil,
            dirty: 0,
            startedAt: 0,
            lastActivity: lastActivity,
            ageSec: 0,
            staleDecay: 0,
            transcriptFound: true
        )
    }

    // No successful poll yet → connecting (initial state, no chrome shown).
    func testConnectionStatusInitiallyConnecting() {
        let s = PollingStore.computeStatus(
            lastError: nil,
            lastSuccessfulPoll: nil,
            now: Date(),
            staleAfter: 6
        )
        XCTAssertEqual(s, .connecting)
    }

    // Successful refresh → connected.
    func testConnectionStatusConnectedOnSuccess() {
        let now = Date()
        let s = PollingStore.computeStatus(
            lastError: nil,
            lastSuccessfulPoll: now.addingTimeInterval(-1),
            now: now,
            staleAfter: 6
        )
        XCTAssertEqual(s, .connected)
    }

    // Transient hiccup (failed but recent prior success) does NOT flip to stale.
    func testConnectionStatusTransientErrorStaysConnected() {
        let now = Date()
        let s = PollingStore.computeStatus(
            lastError: "endpoint=/api/live error=timeout",
            lastSuccessfulPoll: now.addingTimeInterval(-3),
            now: now,
            staleAfter: 6
        )
        XCTAssertEqual(s, .connected)
    }

    // Sustained failure beyond the staleAfter threshold flips to stale with elapsed-seconds payload.
    func testConnectionStatusStaleAfterThreshold() {
        let now = Date()
        let s = PollingStore.computeStatus(
            lastError: "endpoint=/api/live error=ECONNREFUSED",
            lastSuccessfulPoll: now.addingTimeInterval(-15),
            now: now,
            staleAfter: 6
        )
        XCTAssertEqual(s, .stale(secondsSinceSuccess: 15))
    }

    // No prior success at all + an error → still .connecting (we never got data, "stale" isn't the right word).
    func testConnectionStatusErrorBeforeFirstSuccessIsConnecting() {
        let s = PollingStore.computeStatus(
            lastError: "endpoint=/api/live error=ECONNREFUSED",
            lastSuccessfulPoll: nil,
            now: Date(),
            staleAfter: 6
        )
        XCTAssertEqual(s, .connecting)
    }
}
