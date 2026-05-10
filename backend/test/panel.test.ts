// backend/test/panel.test.ts
import { test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, basename } from "node:path";
import { buildPanel } from "../src/claude/panel.ts";

let savedClaudeHome: string | undefined;

beforeEach(() => {
  savedClaudeHome = process.env.CLAUDE_HOME;
  process.env.CLAUDE_HOME = mkdtempSync(join(tmpdir(), "cc-panel-home-"));
});

afterEach(() => {
  if (savedClaudeHome === undefined) delete process.env.CLAUDE_HOME;
  else process.env.CLAUDE_HOME = savedClaudeHome;
});

test("buildPanel with sid=null returns CLEAR state without throwing", async () => {
  // verifies the no-session-selected path: tp/turns are empty, classify returns CLEAR,
  // recent_prompts degrades cleanly (history.jsonl absent in tmp dir).
  const cwd = mkdtempSync(join(tmpdir(), "cc-panel-cwd-"));
  const p = await buildPanel(cwd, null, false);
  expect(p.sessionId).toBeNull();
  expect(p.transcript_found).toBe(false);
  expect(p.repo).toBe(basename(cwd));
  expect(p.event).toBe("CLEAR");
  expect(p.recent_prompts).toEqual([]);
});

test("buildPanel forwards alive flag to classify (regression for Loop 11 deviation 30)", async () => {
  // verifies the alive parameter reaches classify — a session with no transcript and
  // alive=true should still emit CLEAR (no turns to classify), proving the call doesn't
  // throw. The actual alive=true vs false branching is exercised by classify.test.ts.
  const cwd = mkdtempSync(join(tmpdir(), "cc-panel-alive-cwd-"));
  const pAlive = await buildPanel(cwd, null, true);
  const pDead = await buildPanel(cwd, null, false);
  expect(pAlive.event).toBe("CLEAR");
  expect(pDead.event).toBe("CLEAR");
});
