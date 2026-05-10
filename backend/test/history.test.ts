// backend/test/history.test.ts
import { test, expect, afterEach, beforeEach } from "bun:test";
import { mkdtempSync, writeFileSync, rmSync, existsSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { recentPromptsForCwd } from "../src/claude/history.ts";

const SAVED_CLAUDE_HOME = process.env.CLAUDE_HOME;
let fixtureRoot = "";

function writeHistory(lines: string[]): void {
  writeFileSync(join(fixtureRoot, "history.jsonl"), lines.join("\n"), "utf-8");
}

beforeEach(() => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "cc-dashboard-history-"));
  process.env.CLAUDE_HOME = fixtureRoot;
});

afterEach(() => {
  if (SAVED_CLAUDE_HOME === undefined) delete process.env.CLAUDE_HOME;
  else process.env.CLAUDE_HOME = SAVED_CLAUDE_HOME;
  if (fixtureRoot.length > 0) rmSync(fixtureRoot, { recursive: true, force: true });
});

// Verifies prompts for /repo/A are returned most-recent first and limited correctly.
test("recentPromptsForCwd returns A's 2 prompts most-recent first", async () => {
  writeHistory([
    JSON.stringify({ project: "/repo/A", display: "first prompt for A", timestamp: "2026-01-01T00:00:00Z" }),
    JSON.stringify({ project: "/repo/B", display: "prompt for B", timestamp: "2026-01-02T00:00:00Z" }),
    JSON.stringify({ project: "/repo/A", display: "second prompt for A", timestamp: "2026-01-03T00:00:00Z" }),
    "{ this is malformed json",
    "",
  ]);
  const out = await recentPromptsForCwd("/repo/A", 5);
  expect(out.length).toBe(2);
  expect(out[0]?.display).toBe("second prompt for A");
  expect(out[1]?.display).toBe("first prompt for A");
});

// Verifies /repo/B yields exactly the one matching prompt.
test("recentPromptsForCwd returns exactly 1 entry for /repo/B", async () => {
  writeHistory([
    JSON.stringify({ project: "/repo/A", display: "first prompt for A", timestamp: "2026-01-01T00:00:00Z" }),
    JSON.stringify({ project: "/repo/B", display: "prompt for B", timestamp: "2026-01-02T00:00:00Z" }),
    JSON.stringify({ project: "/repo/A", display: "second prompt for A", timestamp: "2026-01-03T00:00:00Z" }),
  ]);
  const out = await recentPromptsForCwd("/repo/B", 5);
  expect(out.length).toBe(1);
  expect(out[0]?.display).toBe("prompt for B");
});

// Verifies an unknown cwd returns the empty list (no match).
test("recentPromptsForCwd returns [] for unseen cwd", async () => {
  writeHistory([
    JSON.stringify({ project: "/repo/A", display: "first prompt for A" }),
    JSON.stringify({ project: "/repo/B", display: "prompt for B" }),
  ]);
  const out = await recentPromptsForCwd("/repo/never-seen", 5);
  expect(out).toEqual([]);
});

// Verifies malformed JSON and blank lines are silently skipped without throwing.
test("recentPromptsForCwd silently skips malformed and blank lines", async () => {
  writeHistory([
    JSON.stringify({ project: "/repo/A", display: "good A prompt" }),
    "{ broken",
    "",
    "   ",
    JSON.stringify({ project: "/repo/A", display: "another good A prompt" }),
  ]);
  let result: { display: string; timestamp?: string }[] = [];
  await expect(
    (async () => {
      result = await recentPromptsForCwd("/repo/A", 5);
    })(),
  ).resolves.toBeUndefined();
  expect(result.length).toBe(2);
});

// Verifies that limit truncates to the most recent N when more entries exist.
test("recentPromptsForCwd respects limit when more than N entries exist", async () => {
  writeHistory([
    JSON.stringify({ project: "/repo/C", display: "C-1" }),
    JSON.stringify({ project: "/repo/C", display: "C-2" }),
    JSON.stringify({ project: "/repo/C", display: "C-3" }),
    JSON.stringify({ project: "/repo/C", display: "C-4" }),
    JSON.stringify({ project: "/repo/C", display: "C-5" }),
    JSON.stringify({ project: "/repo/C", display: "C-6" }),
  ]);
  const out = await recentPromptsForCwd("/repo/C", 3);
  expect(out.length).toBe(3);
  // Most-recent first: C-6, C-5, C-4
  expect(out.map((e) => e.display)).toEqual(["C-6", "C-5", "C-4"]);
});

// Verifies that a missing history.jsonl returns [] rather than throwing.
test("recentPromptsForCwd returns [] when history file doesn't exist", async () => {
  const path = join(fixtureRoot, "history.jsonl");
  if (existsSync(path)) unlinkSync(path);
  const out = await recentPromptsForCwd("/anywhere", 5);
  expect(out).toEqual([]);
});
