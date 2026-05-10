// backend/test/transcript.test.ts
import { test, expect } from "bun:test";
import { readJsonlTail, lastTurns, extractText } from "../src/claude/transcript.ts";

const FIXTURE = "test/fixtures/dot-claude/projects/-tmp-test-repo/sess-basic.jsonl";

// Verifies happy-path tail read produces all 3 fixture turns starting with the user turn.
test("readJsonlTail returns 3 turns from the fixture", () => {
  const turns = readJsonlTail(FIXTURE, 100);
  expect(turns.length).toBe(3);
  expect(turns[0]?.type).toBe("user");
});

// Verifies missing-file early return is empty (the documented "no transcript" contract).
test("readJsonlTail returns [] for missing file", () => {
  expect(readJsonlTail("does-not-exist.jsonl", 100)).toEqual([]);
});

// Verifies main-thread filter keeps user+assistant turns and rejects nothing in this fixture.
test("lastTurns filters main-thread user/assistant", () => {
  const turns = readJsonlTail(FIXTURE, 100);
  expect(lastTurns(turns, 5).length).toBe(3);
});

// Verifies extractText handles both string content and content-block arrays
// (text passes through; tool_use becomes a `[tool: NAME]` marker).
test("extractText pulls text and tool_use markers", () => {
  expect(extractText("hello")).toBe("hello");
  expect(extractText([{ type: "text", text: "a" }, { type: "tool_use", name: "Bash" }])).toBe("a\n[tool: Bash]");
});
