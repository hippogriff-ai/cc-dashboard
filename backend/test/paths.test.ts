// backend/test/paths.test.ts
import { test, expect } from "bun:test";
import { cwdToEncoded, sessionsDir, projectsDir } from "../src/claude/paths.ts";

// Verifies cwd encoding swaps / and . to - matching `~/.claude/projects/` directory convention.
test("cwdToEncoded replaces / and . with -", () => {
  expect(cwdToEncoded("/Users/foo/work.repo")).toBe("-Users-foo-work-repo");
});

// Guards against silent garbage encodings: empty / non-absolute cwd must throw.
test("cwdToEncoded rejects empty and relative paths", () => {
  expect(() => cwdToEncoded("")).toThrow();
  expect(() => cwdToEncoded("foo")).toThrow();
});

// Verifies sessionsDir lands inside ~/.claude (or $CLAUDE_HOME) at the expected leaf.
test("sessionsDir resolves to ~/.claude/sessions", () => {
  expect(sessionsDir()).toMatch(/\.claude\/sessions$/);
});

// Verifies projectsDir lands at ~/.claude/projects so transcript lookups resolve.
test("projectsDir resolves to ~/.claude/projects", () => {
  expect(projectsDir()).toMatch(/\.claude\/projects$/);
});
