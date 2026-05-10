// backend/test/sessions.test.ts
import { test, expect, afterEach, beforeEach } from "bun:test";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { basename, join } from "node:path";
import { tmpdir } from "node:os";
import { loadLiveSessions } from "../src/claude/sessions.ts";

const SAVED_CLAUDE_HOME = process.env.CLAUDE_HOME;
let fixtureRoot = "";
let fixtureCwd = "";

beforeEach(() => {
  // Each test gets a fresh CLAUDE_HOME pointing at a temp dir with a sessions/ subdir.
  // Also create a non-git fixture cwd so gitInfo() returns deterministic null branch /
  // 0 dirty / null last_commit, independent of the developer's working state.
  fixtureRoot = mkdtempSync(join(tmpdir(), "cc-dashboard-sessions-"));
  mkdirSync(join(fixtureRoot, "sessions"), { recursive: true });
  fixtureCwd = mkdtempSync(join(tmpdir(), "cc-dashboard-cwd-"));
  process.env.CLAUDE_HOME = fixtureRoot;
});

afterEach(() => {
  if (SAVED_CLAUDE_HOME === undefined) delete process.env.CLAUDE_HOME;
  else process.env.CLAUDE_HOME = SAVED_CLAUDE_HOME;
  if (fixtureRoot.length > 0) rmSync(fixtureRoot, { recursive: true, force: true });
  if (fixtureCwd.length > 0) rmSync(fixtureCwd, { recursive: true, force: true });
});

function writeSession(filename: string, body: unknown): void {
  writeFileSync(join(fixtureRoot, "sessions", filename), JSON.stringify(body), "utf-8");
}

// Verifies loadLiveSessions filters out non-interactive entries and surfaces a
// shape-correct LiveSession for the live interactive entry (using current pid).
test("loadLiveSessions returns only the live interactive session", () => {
  writeSession("live.json", {
    kind: "interactive",
    pid: process.pid,
    sessionId: "sid-live-001",
    cwd: fixtureCwd,
    startedAt: Date.now(),
  });
  writeSession("background.json", {
    kind: "background",
    pid: process.pid,
    sessionId: "sid-bg-001",
    cwd: fixtureCwd,
    startedAt: Date.now(),
  });

  const sessions = loadLiveSessions();
  expect(sessions.length).toBe(1);
  const s = sessions[0]!;
  expect(s.sessionId).toBe("sid-live-001");
  expect(s.pid).toBe(process.pid);
  // The production code computes repo via basename(cwd); mirror that exactly
  // here so the assertion matches the contract rather than reimplementing it.
  expect(s.repo).toBe(basename(fixtureCwd));
  // Non-git fixture dir: gitInfo() returns null branch / 0 dirty / null commit.
  expect(s.branch).toBeNull();
  expect(s.dirty).toBe(0);
  expect(Number.isFinite(s.priority)).toBe(true);
  expect(s.priority).toBeGreaterThanOrEqual(0);
});

// Verifies that an interactive entry with a dead pid is filtered out (liveness gate).
test("loadLiveSessions filters out sessions whose pid is dead", () => {
  writeSession("dead.json", {
    kind: "interactive",
    pid: 99999998,
    sessionId: "sid-dead-001",
    cwd: fixtureCwd,
    startedAt: Date.now(),
  });
  expect(loadLiveSessions()).toEqual([]);
});

// Verifies a malformed JSON file is silently skipped (not thrown), per the
// contract that one bad file shouldn't break enumeration of valid neighbours.
test("loadLiveSessions silently skips malformed JSON files", () => {
  writeFileSync(join(fixtureRoot, "sessions", "broken.json"), "{ this is not json", "utf-8");
  writeSession("live.json", {
    kind: "interactive",
    pid: process.pid,
    sessionId: "sid-live-002",
    cwd: fixtureCwd,
    startedAt: Date.now(),
  });
  const sessions = loadLiveSessions();
  expect(sessions.length).toBe(1);
  expect(sessions[0]!.sessionId).toBe("sid-live-002");
});

// Verifies that an interactive entry missing cwd is skipped — gitInfo("") and
// basename("") would silently yield empty/null fields, masking the bad record.
test("loadLiveSessions skips sessions with empty or missing cwd", () => {
  writeSession("nocwd.json", {
    kind: "interactive",
    pid: process.pid,
    sessionId: "sid-nocwd-001",
    startedAt: Date.now(),
  });
  writeSession("emptycwd.json", {
    kind: "interactive",
    pid: process.pid,
    sessionId: "sid-emptycwd-001",
    cwd: "",
    startedAt: Date.now(),
  });
  expect(loadLiveSessions()).toEqual([]);
});
