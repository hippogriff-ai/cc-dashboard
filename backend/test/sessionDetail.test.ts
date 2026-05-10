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

test("buildSessionDetail context_limit is 200K for low usage", () => {
  // Sessions on either tier that haven't grown past 200K still report 200K.
  // Pessimistic for fresh 1M sessions, but accurate for 200K-tier users.
  const state = emptyState();
  const s = getOrCreateSession(state, "sid-low", "/repo/z");
  s.tokens.input = 50_000;
  s.tokens.cached_read = 30_000;
  s.tokens.cached_create = 10_000;
  s.tokens.output = 5_000;
  const d = buildSessionDetail(state, "sid-low");
  expect(d?.tokens.context_limit).toBe(200_000);
});

test("buildSessionDetail context_limit is 1M when observed input+cache exceeds 200K", () => {
  // The transcript records `claude-opus-4-7` for both 200K and 1M variants
  // (no [1m] suffix) — but a 200K-window model can't bill input past its
  // own limit, so observed > 200K is a sound 1M-tier signal.
  const state = emptyState();
  const s = getOrCreateSession(state, "sid-1m", "/repo/big");
  s.tokens.input = 5_000;
  s.tokens.cached_read = 250_000;   // alone exceeds 200K → must be 1M tier
  s.tokens.cached_create = 0;
  s.tokens.output = 10_000;         // output excluded from threshold check
  const d = buildSessionDetail(state, "sid-1m");
  expect(d?.tokens.context_limit).toBe(1_000_000);
});

test("buildSessionDetail context_limit excludes output_tokens from the threshold check", () => {
  // Output tokens are billed separately and don't count against the input
  // context window — including them in the tier-detection signal would
  // misclassify chatty 200K sessions as 1M.
  const state = emptyState();
  const s = getOrCreateSession(state, "sid-out", "/repo/out");
  s.tokens.input = 100_000;
  s.tokens.cached_read = 50_000;
  s.tokens.cached_create = 0;
  s.tokens.output = 500_000;        // huge output but input total < 200K
  const d = buildSessionDetail(state, "sid-out");
  expect(d?.tokens.context_limit).toBe(200_000);
});
