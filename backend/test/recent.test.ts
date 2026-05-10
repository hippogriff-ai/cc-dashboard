// backend/test/recent.test.ts
import { test, expect, afterEach, beforeEach } from "bun:test";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, utimesSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { loadRecentByRepo } from "../src/claude/recent.ts";

const SAVED_CLAUDE_HOME = process.env.CLAUDE_HOME;
let fixtureRoot = "";
let fixtureCwdA = "";
let fixtureCwdB = "";
const tempCwdsToCleanup: string[] = [];

function writeJsonl(path: string, lines: object[]): void {
  writeFileSync(path, lines.map((l) => JSON.stringify(l)).join("\n") + "\n", "utf-8");
}

function makeBasicTurns(cwd: string): object[] {
  return [
    {
      type: "user",
      cwd,
      isSidechain: false,
      message: { role: "user", content: "hello" },
      timestamp: "2026-01-01T00:00:00Z",
      uuid: "u-1",
    },
    {
      type: "assistant",
      cwd,
      isSidechain: false,
      message: { role: "assistant", content: [{ type: "text", text: "hi back" }] },
      timestamp: "2026-01-01T00:00:01Z",
      uuid: "a-1",
    },
  ];
}

beforeEach(() => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "cc-dashboard-recent-"));
  mkdirSync(join(fixtureRoot, "projects"), { recursive: true });
  fixtureCwdA = mkdtempSync(join(tmpdir(), "cc-dashboard-cwdA-"));
  fixtureCwdB = mkdtempSync(join(tmpdir(), "cc-dashboard-cwdB-"));
  tempCwdsToCleanup.push(fixtureCwdA, fixtureCwdB);
  process.env.CLAUDE_HOME = fixtureRoot;
});

afterEach(() => {
  if (SAVED_CLAUDE_HOME === undefined) delete process.env.CLAUDE_HOME;
  else process.env.CLAUDE_HOME = SAVED_CLAUDE_HOME;
  if (fixtureRoot.length > 0) rmSync(fixtureRoot, { recursive: true, force: true });
  while (tempCwdsToCleanup.length > 0) {
    const p = tempCwdsToCleanup.pop()!;
    rmSync(p, { recursive: true, force: true });
  }
});

// Verifies anchored SKIP_PATTERNS exclude only encoded dir names that BEGIN
// with -private-var-folders- or -test-repo, while a legitimate user repo
// whose path happens to contain "test-repo" mid-string is preserved.
test("loadRecentByRepo returns 2 rows after SKIP_PATTERNS exclusion", async () => {
  const projA = join(fixtureRoot, "projects", "-Users-foo-projA");
  const projB = join(fixtureRoot, "projects", "-Users-foo-projB");
  const projSkip1 = join(fixtureRoot, "projects", "-private-var-folders-xyz");
  // Encoded form of /test-repo/something — must have leading `-` to match anchored pattern.
  const projSkip2 = join(fixtureRoot, "projects", "-test-repo-something");
  mkdirSync(projA, { recursive: true });
  mkdirSync(projB, { recursive: true });
  mkdirSync(projSkip1, { recursive: true });
  mkdirSync(projSkip2, { recursive: true });

  writeJsonl(join(projA, "sess-1.jsonl"), makeBasicTurns(fixtureCwdA));
  writeJsonl(join(projA, "sess-2.jsonl"), makeBasicTurns(fixtureCwdA));
  writeJsonl(join(projB, "sess-3.jsonl"), makeBasicTurns(fixtureCwdB));
  writeJsonl(join(projSkip1, "sess-bad.jsonl"), makeBasicTurns("/nope-1"));
  writeJsonl(join(projSkip2, "sess-skip.jsonl"), makeBasicTurns("/nope-2"));

  // Make sess-2 newer than sess-1 to force dedup outcome.
  const now = new Date();
  const earlier = new Date(now.getTime() - 60 * 1000);
  utimesSync(join(projA, "sess-1.jsonl"), earlier, earlier);
  utimesSync(join(projA, "sess-2.jsonl"), now, now);

  const rows = await loadRecentByRepo(30);
  expect(rows.length).toBe(2);
  const cwds = rows.map((r) => r.cwd).sort();
  expect(cwds).toEqual([fixtureCwdA, fixtureCwdB].sort());
});

// Verifies the dedup picks the newer session (sess-2) for cwd A.
test("loadRecentByRepo dedup keeps newer sess-2 over sess-1 for the same cwd", async () => {
  const projA = join(fixtureRoot, "projects", "-Users-foo-projA");
  mkdirSync(projA, { recursive: true });
  writeJsonl(join(projA, "sess-1.jsonl"), makeBasicTurns(fixtureCwdA));
  writeJsonl(join(projA, "sess-2.jsonl"), makeBasicTurns(fixtureCwdA));
  const now = new Date();
  const earlier = new Date(now.getTime() - 60 * 1000);
  utimesSync(join(projA, "sess-1.jsonl"), earlier, earlier);
  utimesSync(join(projA, "sess-2.jsonl"), now, now);

  const rows = await loadRecentByRepo(30);
  const a = rows.find((r) => r.cwd === fixtureCwdA);
  expect(a).toBeDefined();
  expect(a!.sessionId).toBe("sess-2");
});

// Verifies sort order is descending by last_activity (most recent first).
test("loadRecentByRepo sorts rows by last_activity descending", async () => {
  const projA = join(fixtureRoot, "projects", "-Users-foo-projA");
  const projB = join(fixtureRoot, "projects", "-Users-foo-projB");
  mkdirSync(projA, { recursive: true });
  mkdirSync(projB, { recursive: true });
  writeJsonl(join(projA, "sess-A.jsonl"), makeBasicTurns(fixtureCwdA));
  writeJsonl(join(projB, "sess-B.jsonl"), makeBasicTurns(fixtureCwdB));

  // Make B clearly newer than A.
  const now = new Date();
  const older = new Date(now.getTime() - 5 * 60 * 1000);
  utimesSync(join(projA, "sess-A.jsonl"), older, older);
  utimesSync(join(projB, "sess-B.jsonl"), now, now);

  const rows = await loadRecentByRepo(30);
  expect(rows.length).toBe(2);
  expect(rows[0]!.last_activity).toBeGreaterThanOrEqual(rows[1]!.last_activity);
  expect(rows[0]!.cwd).toBe(fixtureCwdB);
});

// Verifies a strict cutoff (days=0.0001) filters out sessions older than the threshold.
test("loadRecentByRepo filters out sessions older than the cutoff", async () => {
  const projA = join(fixtureRoot, "projects", "-Users-foo-projA");
  const projB = join(fixtureRoot, "projects", "-Users-foo-projB");
  mkdirSync(projA, { recursive: true });
  mkdirSync(projB, { recursive: true });
  writeJsonl(join(projA, "sess-1.jsonl"), makeBasicTurns(fixtureCwdA));
  writeJsonl(join(projA, "sess-2.jsonl"), makeBasicTurns(fixtureCwdA));
  writeJsonl(join(projB, "sess-3.jsonl"), makeBasicTurns(fixtureCwdB));

  // Push every transcript's mtime to 30 days ago, then ask for cutoff=0.0001 days.
  const longAgo = new Date(Date.now() - 30 * 86400 * 1000);
  utimesSync(join(projA, "sess-1.jsonl"), longAgo, longAgo);
  utimesSync(join(projA, "sess-2.jsonl"), longAgo, longAgo);
  utimesSync(join(projB, "sess-3.jsonl"), longAgo, longAgo);

  expect(await loadRecentByRepo(0.0001)).toEqual([]);
});

// Verifies that a row whose cwd doesn't exist on disk is filtered from output.
test("loadRecentByRepo drops rows whose cwd no longer exists", async () => {
  const projGhost = join(fixtureRoot, "projects", "-nonexistent-path-xyz");
  mkdirSync(projGhost, { recursive: true });
  writeJsonl(join(projGhost, "sess-ghost.jsonl"), makeBasicTurns("/nonexistent/path/xyz"));

  const projA = join(fixtureRoot, "projects", "-Users-foo-projA");
  mkdirSync(projA, { recursive: true });
  writeJsonl(join(projA, "sess-A.jsonl"), makeBasicTurns(fixtureCwdA));

  const rows = await loadRecentByRepo(30);
  expect(rows.length).toBe(1);
  expect(rows[0]!.cwd).toBe(fixtureCwdA);
});

// Regression: a legitimate user repo whose path mid-segment contains
// "test-repo" (e.g. ~/work/my-test-repo-tools) must NOT be excluded by the
// anchored SKIP_PATTERNS. Pre-anchor, the loose /test-repo/ dropped it.
test("loadRecentByRepo preserves a repo whose path contains 'test-repo' mid-string", async () => {
  const projMid = join(fixtureRoot, "projects", "-Users-foo-work-my-test-repo-tools");
  mkdirSync(projMid, { recursive: true });
  writeJsonl(join(projMid, "sess-mid.jsonl"), makeBasicTurns(fixtureCwdA));

  const rows = await loadRecentByRepo(30);
  expect(rows.length).toBe(1);
  expect(rows[0]!.cwd).toBe(fixtureCwdA);
});

// Regression: when firstCwd returns null (no JSONL line in the first 64KB
// carries a cwd field), the row must be dropped rather than fabricated from
// the lossy reverse-encoded directory name.
test("loadRecentByRepo drops a row whose transcript has no cwd in first 64KB", async () => {
  const projA = join(fixtureRoot, "projects", "-Users-foo-projA");
  mkdirSync(projA, { recursive: true });
  // A JSONL whose only line lacks a `cwd` field — firstCwd returns null.
  writeJsonl(join(projA, "sess-nocwd.jsonl"), [
    { type: "user", isSidechain: false, message: { role: "user", content: "hi" }, timestamp: "2026-01-01T00:00:00Z", uuid: "u-1" },
  ]);

  expect(await loadRecentByRepo(30)).toEqual([]);
});
