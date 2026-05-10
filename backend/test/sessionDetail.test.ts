// backend/test/sessionDetail.test.ts
import { test, expect } from "bun:test";
import { buildSessionDetail } from "../src/claude/sessionDetail.ts";
import { emptyState, getOrCreateSession } from "../src/corpus/indices.ts";

test("buildSessionDetail returns null for unknown sid", () => {
  // verifies the documented null-return contract: caller must map null → 404, not 500.
  const state = emptyState();
  expect(buildSessionDetail(state, "no-such-sid")).toBeNull();
});

test("buildSessionDetail returns the latest branch from branchTimeline", () => {
  // verifies branch resolves to last entry (consecutive-dedup contract from tail.ts)
  const state = emptyState();
  const s = getOrCreateSession(state, "sid-x", "/repo/x");
  s.branchTimeline.push({ ts: 1, branch: "main" });
  s.branchTimeline.push({ ts: 2, branch: "feat" });
  s.branchTimeline.push({ ts: 3, branch: "main" });
  const d = buildSessionDetail(state, "sid-x");
  expect(d?.branch).toBe("main");
  expect(d?.branch_history).toEqual(["main", "feat", "main"]);
});

test("buildSessionDetail decisions array is a defensive copy (mutation does not corrupt corpus)", () => {
  // verifies Loop 11 deviation 30: returning a live ref would let consumers mutate
  // state.decisionsByCwd via .splice/.sort. Spread isolates the response.
  const state = emptyState();
  getOrCreateSession(state, "sid-y", "/repo/y");
  state.decisionsByCwd.set("/repo/y", [
    { q: "Q1?", a: "A1" },
    { q: "Q2?", a: "A2" },
  ]);
  const d = buildSessionDetail(state, "sid-y");
  expect(d?.decisions.length).toBe(2);
  d?.decisions.splice(0, 1);
  // Live corpus must still have both entries.
  expect(state.decisionsByCwd.get("/repo/y")?.length).toBe(2);
});
