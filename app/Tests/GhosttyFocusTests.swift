// Mirrors the TS tests in `backend/test/{tokenize,score}.test.ts` so the
// Swift port of the Ghostty focus pipeline preserves behaviour exactly.
// Plus a small fixture-driven test for `sessionPrompts` that proves the
// transcript reader filters sidechain / IDE-injected / system-reminder
// turns and respects the 5-early / 3-recent slicing.
import XCTest
@testable import cc_dashboard

final class GhosttyFocusTokenizeTests: XCTestCase {
    /// TS: "strips stopwords + short tokens".
    func testStripsStopwordsAndShortTokens() {
        let toks = tokenize("the quick fox is on a log")
        XCTAssertFalse(toks.contains("the"))
        XCTAssertFalse(toks.contains("is"))
        XCTAssertFalse(toks.contains("on"))
        XCTAssertFalse(toks.contains("a"))
        XCTAssertTrue(toks.contains("quick"))
        XCTAssertTrue(toks.contains("fox"))
        XCTAssertTrue(toks.contains("log"))
    }

    /// TS: "strips %-encoding".
    func testStripsPercentEncoding() {
        let toks = tokenize("foo%20bar%2Fbaz")
        XCTAssertTrue(toks.contains("foo"))
        XCTAssertTrue(toks.contains("bar"))
        XCTAssertTrue(toks.contains("baz"))
    }

    /// TS: "normalizes unicode" — diacritics removed via NFKD + ASCII filter.
    func testNormalizesUnicode() {
        let toks = tokenize("café résumé")
        XCTAssertTrue(toks.contains("cafe"))
        XCTAssertTrue(toks.contains("resume"))
    }

    /// TS: "rejects pure-numeric tokens" — "123" out, "abc123" in.
    func testRejectsPureNumericTokens() {
        let toks = tokenize("123 456 abc123 hello")
        XCTAssertFalse(toks.contains("123"))
        XCTAssertFalse(toks.contains("456"))
        XCTAssertTrue(toks.contains("abc123"))
        XCTAssertTrue(toks.contains("hello"))
    }

    func testEmptyInput() {
        XCTAssertEqual(tokenize(""), [])
    }
}

final class GhosttyFocusScoreTests: XCTestCase {
    /// TS: "early hits weighted 3, cwd 2, recent 1".
    func testEarlyCwdRecentWeights() {
        let r = scoreWindow(
            window: ["alpha", "beta", "gamma"],
            early:  ["alpha"],
            recent: ["gamma"],
            cwd:    ["beta"]
        )
        XCTAssertEqual(r.score, 6)
        XCTAssertEqual(r.hits.sorted(), ["alpha", "beta", "gamma"])
    }

    /// TS: "no double-count when token in two buckets".
    func testNoDoubleCount() {
        let r = scoreWindow(
            window: ["alpha"],
            early:  ["alpha"],
            recent: ["alpha"],
            cwd:    ["alpha"]
        )
        XCTAssertEqual(r.score, 3)
        XCTAssertEqual(r.hits, ["alpha"])
    }

    /// TS: "zero overlap → score 0".
    func testZeroOverlap() {
        let r = scoreWindow(
            window: ["alpha", "beta"],
            early:  ["x"],
            recent: ["z"],
            cwd:    ["y"]
        )
        XCTAssertEqual(r.score, 0)
        XCTAssertEqual(r.hits, [])
    }
}

final class GhosttyFocusSessionPromptsTests: XCTestCase {
    /// `sessionPrompts` reads from `$CLAUDE_HOME/projects/<encoded>/<sid>.jsonl`.
    /// Set CLAUDE_HOME to a temp dir, write a fake transcript, and assert the
    /// extracted prompts match the filter contract (skip sidechain, skip
    /// `<ide_selection>` / `<system-reminder>`, slice into early[0..<5] +
    /// recent[-3:] when total > 5).
    func testReadsAndFiltersTranscript() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cc-dash-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // /tmp/test-repo encodes to "-tmp-test-repo".
        let cwd = "/tmp/test-repo"
        let sid = "abc123"
        let projects = tmp
            .appendingPathComponent("projects")
            .appendingPathComponent("-tmp-test-repo")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let jsonl = projects.appendingPathComponent("\(sid).jsonl")

        // 7 user prompts total: prompts 1-5 → early, prompts 6-7 → recent
        // (7 - 5 = 2, but recent slice is last-3 when total > 5, so we get
        // prompts 5,6,7 — that's the TS behaviour: `slice(-3)` on the full
        // array, not just the tail beyond early). Plus three filtered turns
        // (sidechain, ide_selection, system-reminder) that must be excluded.
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"first prompt"}}"#,
            #"{"type":"user","message":{"role":"user","content":"second prompt"}}"#,
            #"{"type":"user","message":{"role":"user","content":"third prompt"}}"#,
            #"{"type":"user","message":{"role":"user","content":"fourth prompt"}}"#,
            #"{"type":"user","message":{"role":"user","content":"fifth prompt"}}"#,
            #"{"type":"user","isSidechain":true,"message":{"role":"user","content":"sidechain - exclude"}}"#,
            #"{"type":"user","message":{"role":"user","content":"<ide_selection>x</ide_selection>"}}"#,
            #"{"type":"user","message":{"role":"user","content":"<system-reminder>y</system-reminder>"}}"#,
            #"{"type":"user","message":{"role":"user","content":"sixth prompt"}}"#,
            #"{"type":"user","message":{"role":"user","content":"seventh prompt"}}"#,
        ]
        try lines.joined(separator: "\n").write(to: jsonl, atomically: true, encoding: .utf8)

        // Inject CLAUDE_HOME so findTranscript points at our tmp dir.
        setenv("CLAUDE_HOME", tmp.path, 1)
        defer { unsetenv("CLAUDE_HOME") }

        let prompts = sessionPrompts(cwd: cwd, sid: sid)
        XCTAssertEqual(prompts.early, [
            "first prompt", "second prompt", "third prompt",
            "fourth prompt", "fifth prompt"
        ])
        // 7 valid prompts > 5, so recent = last 3 of the full list.
        XCTAssertEqual(prompts.recent, ["fifth prompt", "sixth prompt", "seventh prompt"])
    }

    func testReturnsEmptyWhenSidNil() {
        let r = sessionPrompts(cwd: "/tmp/whatever", sid: nil)
        XCTAssertEqual(r.early, [])
        XCTAssertEqual(r.recent, [])
    }

    func testReturnsEmptyWhenTranscriptMissing() {
        let r = sessionPrompts(cwd: "/tmp/nonexistent-\(UUID().uuidString)", sid: "x")
        XCTAssertEqual(r.early, [])
        XCTAssertEqual(r.recent, [])
    }
}
