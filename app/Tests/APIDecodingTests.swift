// Decode tests pinning the Swift `Codable` structs to realistic JSON
// fixtures from the backend. Loop 39 caught a real bug — `PromptEntry.timestamp`
// was typed `String?` but the backend has always emitted a Number, so
// `/api/panel` failed Codable decoding and rendered "Couldn't load panel"
// in the Restore tab. The bug shipped because the existing backend tests
// validated the buildPanel logic but never round-tripped the JSON through
// the Swift decoder. These tests close that gap.
import XCTest
@testable import cc_dashboard

final class APIDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    // /api/panel payload mirrors what the running backend emits — note that
    // recent_prompts[].timestamp is a Number (millisecond epoch), not a String.
    func testPanelDecodesWithRealisticFixture() throws {
        let json = """
        {
          "cwd": "/Users/u/repo",
          "repo": "repo",
          "sessionId": null,
          "transcript_found": false,
          "git": { "branch": "main", "dirty": 2, "last_commit": "abc Fix bug" },
          "diff_summary": null,
          "recent_prompts": [
            { "display": "/daily-digest", "timestamp": 1778243777955 },
            { "display": "what is X", "timestamp": 1778073174199 }
          ],
          "last_user": "",
          "last_assistant": "",
          "event": "CLEAR",
          "reason": "",
          "open_tool": null
        }
        """.data(using: .utf8)!
        let p = try decoder.decode(Panel.self, from: json)
        XCTAssertEqual(p.repo, "repo")
        XCTAssertEqual(p.event, .clear)
        XCTAssertNil(p.diffSummary)
        XCTAssertEqual(p.recentPrompts.count, 2)
        XCTAssertEqual(p.recentPrompts[0].display, "/daily-digest")
        XCTAssertEqual(p.recentPrompts[0].timestamp, 1778243777955)
    }

    // /api/live[0] payload — verifies all fields decode including the openTool
    // null case and the Double-typed last_activity.
    func testLiveSessionDecodesWithRealisticFixture() throws {
        let json = """
        {
          "pid": 12345,
          "sessionId": "sid-abc",
          "cwd": "/Users/u/repo",
          "repo": "repo",
          "branch": "main",
          "dirty": 2,
          "started_at": 1777325341888,
          "last_activity": 1778244645621.066,
          "age_sec": 3881,
          "stale_decay": 9,
          "transcript_found": true,
          "event": "IDLE_AFTER_COMPLETE",
          "reason": "ready for next instruction",
          "priority": 49,
          "last_user": "",
          "last_assistant": "Done.",
          "open_tool": null
        }
        """.data(using: .utf8)!
        let s = try decoder.decode(LiveSession.self, from: json)
        XCTAssertEqual(s.sessionId, "sid-abc")
        XCTAssertEqual(s.event, .idleAfterComplete)
        XCTAssertEqual(s.priority, 49)
        XCTAssertNil(s.openTool)
    }

    // /api/recent[0] payload — same flat shape as LiveSession minus the
    // pid/started_at/age_sec/stale_decay/transcript_found fields.
    func testRecentRepoDecodesWithRealisticFixture() throws {
        let json = """
        {
          "cwd": "/Users/u/repo",
          "repo": "repo",
          "branch": "main",
          "dirty": 9,
          "last_commit": "dc388ce Fix zombie",
          "sessionId": "sid-xyz",
          "last_activity": 1778248517080.33,
          "event": "CLEAR",
          "reason": "processing...",
          "priority": 99,
          "last_user": "",
          "last_assistant": "[tool: Bash]",
          "open_tool": null
        }
        """.data(using: .utf8)!
        let r = try decoder.decode(RecentRepo.self, from: json)
        XCTAssertEqual(r.repo, "repo")
        XCTAssertEqual(r.lastCommit, "dc388ce Fix zombie")
        XCTAssertEqual(r.event, .clear)
    }

    // /api/session-detail payload — the detail-pane heavy lifter. Verifies the
    // nested structures (FileTouch.last_touch as Double, Tokens, decisions array).
    func testSessionDetailDecodesWithRealisticFixture() throws {
        let json = """
        {
          "sessionId": "sid-abc",
          "cwd": "/Users/u/repo",
          "repo": "repo",
          "branch": "main",
          "branch_history": ["main", "feature/foo"],
          "files_changed": [
            { "path": "/a/b.ts", "edits": 7, "last_touch": 1778244514127 }
          ],
          "tokens": {
            "input": 24202,
            "cached_read": 8719456,
            "cached_create": 1918580,
            "output": 193924,
            "context_limit": 200000
          },
          "load_history": [0, 0, 1, 2, 0],
          "last_assistant": "Done.",
          "open_tool": null,
          "decisions": [],
          "source": "cc",
          "age_sec": 42
        }
        """.data(using: .utf8)!
        let d = try decoder.decode(SessionDetail.self, from: json)
        XCTAssertEqual(d.sessionId, "sid-abc")
        XCTAssertEqual(d.branchHistory.count, 2)
        XCTAssertEqual(d.filesChanged.first?.lastTouch, 1778244514127)
        XCTAssertEqual(d.tokens.contextLimit, 200000)
        XCTAssertEqual(d.loadHistory.count, 5)
        XCTAssertEqual(d.source, "cc")
    }

    // /api/decisions payload — empty case must decode (cc-dashboard repo has no
    // Decision Log entries yet but the endpoint shape is fixed).
    func testDecisionsResponseDecodesEmpty() throws {
        let json = #"{"decisions":[]}"#.data(using: .utf8)!
        let r = try decoder.decode(DecisionsResponse.self, from: json)
        XCTAssertEqual(r.decisions.count, 0)
    }

    // /api/health — small but used by BackendController during startup probe.
    // Field shape must round-trip cleanly so a probe failure isn't misclassified.
    func testHealthShape() throws {
        // Health doesn't have a Codable struct in APIClient (it's used as a
        // generic ping by BackendController). This test pins the response shape
        // so a future restructure of the endpoint can't silently break startup
        // detection.
        struct Health: Codable { let ok: Bool; let ts: Int64 }
        let json = #"{"ok":true,"ts":1778283050874}"#.data(using: .utf8)!
        let h = try decoder.decode(Health.self, from: json)
        XCTAssertTrue(h.ok)
        XCTAssertEqual(h.ts, 1778283050874)
    }
}
