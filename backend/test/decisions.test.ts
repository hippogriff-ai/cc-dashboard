// backend/test/decisions.test.ts
import { test, expect } from "bun:test";
import { extractDecisions } from "../src/corpus/decisions.ts";
import { readJsonlTail } from "../src/claude/transcript.ts";

test("extractDecisions yields 2 unique pairs from fixture (dedupes the 3rd)", () => {
  // verifies fixture-based extraction: two distinct Q/A pairs surface; the duplicate-3rd-pair is deduped via hash
  const turns = readJsonlTail("test/fixtures/dot-claude/projects/-tmp-test-repo/sess-decisions.jsonl", 100);
  const pairs = extractDecisions(turns);
  expect(pairs.length).toBe(2);
  expect(pairs[0]?.q).toContain("ORM");
  expect(pairs[1]?.q).toContain("integration tests");
});

test("extractDecisions skips long replies", () => {
  // verifies MAX_REPLY_LEN guard — replies over 200 chars are filtered out
  const turns = [
    { type: "assistant", message: { role: "assistant", content: [{ type: "text", text: "Why?" }] } },
    { type: "user", message: { role: "user", content: "x".repeat(500) } },
  ];
  expect(extractDecisions(turns as never).length).toBe(0);
});

test("extractDecisions dedupes by raw (q, a) without hash collisions", () => {
  // verifies the dedup uses the raw string Set (Loop 9 deviation 23) — two
  // distinct pairs that would have collided under a 32-bit int hash both survive
  const turns = [
    { type: "assistant", message: { role: "assistant", content: [{ type: "text", text: "Q one?" }] } },
    { type: "user", message: { role: "user", content: "answer one" } },
    { type: "assistant", message: { role: "assistant", content: [{ type: "text", text: "Q two?" }] } },
    { type: "user", message: { role: "user", content: "answer two" } },
    { type: "assistant", message: { role: "assistant", content: [{ type: "text", text: "Q one?" }] } },
    { type: "user", message: { role: "user", content: "answer one" } },
  ];
  const pairs = extractDecisions(turns as never);
  expect(pairs.length).toBe(2);
  expect(pairs[0]?.q).toContain("Q one");
  expect(pairs[1]?.q).toContain("Q two");
});
