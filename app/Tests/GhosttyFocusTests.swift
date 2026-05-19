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

    /// assistant_last contributes weight 2 (same as cwd) — fills the gap
    /// for drifted sessions where early/recent prompts are stale.
    func testAssistantHitsWeight2() {
        let r = scoreWindow(
            window: ["caching", "techniques"],
            early:  [],
            recent: [],
            cwd:    [],
            assistant: ["caching", "techniques"]
        )
        XCTAssertEqual(r.score, 4)
        XCTAssertEqual(r.assistantHits.sorted(), ["caching", "techniques"])
        XCTAssertEqual(r.hits.sorted(), ["caching", "techniques"])
    }

    /// When a token is in BOTH early and assistant, it's counted once at
    /// the higher (early = 3) weight — assistant comes second in priority.
    func testAssistantDoesNotDoubleCountWithEarly() {
        let r = scoreWindow(
            window:    ["alpha"],
            early:     ["alpha"],
            recent:    [],
            cwd:       [],
            assistant: ["alpha"]
        )
        XCTAssertEqual(r.score, 3)
        XCTAssertEqual(r.hits, ["alpha"])
    }

    /// Pure assistant hit + pure cwd hit accumulate independently when the
    /// tokens are different. 2 (cwd) + 2 (assistant) = 4.
    func testAssistantAndCwdAccumulate() {
        let r = scoreWindow(
            window:    ["project", "caching"],
            early:     [],
            recent:    [],
            cwd:       ["project"],
            assistant: ["caching"]
        )
        XCTAssertEqual(r.score, 4)
    }

    /// Score with no assistant signal (default empty) matches the original
    /// 3-bucket behaviour — guards against accidental regressions.
    func testEmptyAssistantDefaultsToOriginalBehavior() {
        let r = scoreWindow(
            window: ["alpha", "beta", "gamma"],
            early:  ["alpha"],
            recent: ["gamma"],
            cwd:    ["beta"]
        )
        XCTAssertEqual(r.score, 6)
        XCTAssertEqual(r.assistantHits, [])
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
        // Fixture has no assistant turns, so lastAssistant is nil.
        XCTAssertNil(prompts.lastAssistant)
    }

    func testReturnsEmptyWhenSidNil() {
        let r = sessionPrompts(cwd: "/tmp/whatever", sid: nil)
        XCTAssertEqual(r.early, [])
        XCTAssertEqual(r.recent, [])
        XCTAssertNil(r.lastAssistant)
    }

    func testReturnsEmptyWhenTranscriptMissing() {
        let r = sessionPrompts(cwd: "/tmp/nonexistent-\(UUID().uuidString)", sid: "x")
        XCTAssertEqual(r.early, [])
        XCTAssertEqual(r.recent, [])
        XCTAssertNil(r.lastAssistant)
    }

    /// Captures the latest assistant text turn (post-compact recap, etc.).
    /// String-content turns are taken as-is; block-content turns concat all
    /// text blocks and skip thinking/tool_use. Latest-in-file-order wins.
    func testExtractsLastAssistantTurn() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cc-dash-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cwd = "/tmp/asst-repo"
        let sid = "abc"
        let projects = tmp.appendingPathComponent("projects").appendingPathComponent("-tmp-asst-repo")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let jsonl = projects.appendingPathComponent("\(sid).jsonl")

        let lines = [
            #"{"type":"user","message":{"role":"user","content":"first"}}"#,
            // Earlier assistant turn — should be superseded by the latest one.
            #"{"type":"assistant","message":{"role":"assistant","content":"earlier reply"}}"#,
            // Block-content with a text block + a thinking block + a tool_use.
            // Only the text block content should be captured.
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hidden reasoning"},{"type":"text","text":"recap: prompt caching techniques"},{"type":"tool_use","name":"Read","input":{}}]}}"#,
            // Sidechain assistant turn — must be skipped.
            #"{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":"sidechain - exclude"}}"#,
        ]
        try lines.joined(separator: "\n").write(to: jsonl, atomically: true, encoding: .utf8)

        setenv("CLAUDE_HOME", tmp.path, 1)
        defer { unsetenv("CLAUDE_HOME") }

        let r = sessionPrompts(cwd: cwd, sid: sid)
        XCTAssertEqual(r.lastAssistant, "recap: prompt caching techniques")
        // Sidechain was filtered — verify by absence of "sidechain" word.
        XCTAssertFalse(r.lastAssistant?.contains("sidechain") ?? true)
        // Thinking block must NOT leak into the assistant tokens.
        XCTAssertFalse(r.lastAssistant?.contains("hidden reasoning") ?? true)
    }
}
