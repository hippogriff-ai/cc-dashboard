// backend/test/score.test.ts
import { test, expect } from "bun:test";
import { scoreWindow } from "../src/ghostty/score.ts";

// Verifies disjoint early/cwd/recent token buckets contribute 3, 2, and 1 respectively (total 6).
test("early hits weighted 3, cwd 2, recent 1", () => {
  const window = new Set(["alpha", "beta", "gamma"]);
  const early = new Set(["alpha"]);
  const cwd = new Set(["beta"]);
  const recent = new Set(["gamma"]);
  const r = scoreWindow(window, early, recent, cwd);
  expect(r.score).toBe(6);
  expect(r.hits.sort()).toEqual(["alpha", "beta", "gamma"]);
});

// Verifies a token present in early+cwd+recent is counted once at the highest weight (3, not 6).
test("no double-count when token in two buckets", () => {
  const window = new Set(["alpha"]);
  const early = new Set(["alpha"]);
  const cwd = new Set(["alpha"]);
  const recent = new Set(["alpha"]);
  const r = scoreWindow(window, early, recent, cwd);
  expect(r.score).toBe(3);
  expect(r.hits).toEqual(["alpha"]);
});

// Verifies that with no overlap between window tokens and any bucket, the score is zero.
test("zero overlap → score 0", () => {
  const window = new Set(["alpha", "beta"]);
  const early = new Set(["x"]);
  const cwd = new Set(["y"]);
  const recent = new Set(["z"]);
  const r = scoreWindow(window, early, recent, cwd);
  expect(r.score).toBe(0);
  expect(r.hits).toEqual([]);
});
