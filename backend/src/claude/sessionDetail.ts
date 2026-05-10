// backend/src/claude/sessionDetail.ts
import { basename } from "node:path";
import type { SessionDetail } from "../types.ts";
import type { CorpusState, SessionTokens } from "../corpus/indices.ts";
import { decisionsProjection } from "../corpus/projections.ts";

/**
 * Detect which context-window tier the session is on. Claude Code transcripts
 * record the base model id (`claude-opus-4-7`) but not the `[1m]` suffix that
 * marks the 1M-token variant — so we infer from observed cumulative usage:
 * any session whose recorded input + cache exceeds 200K must be on a 1M
 * variant (a 200K-window model can't billed-input past its own limit).
 *
 * Cumulative input/cache slightly overestimates the *current* context window
 * usage (it's a sum across turns, not the last turn's snapshot) but it's a
 * monotone proxy that's correct enough to pick the tier. A separate followup
 * tracks moving to a per-turn peak metric.
 *
 * Falls back to 200K when the observed total fits — accurate for users on
 * the 200K tier, conservative for fresh 1M sessions that haven't grown past
 * 200K yet.
 */
function detectContextLimit(t: SessionTokens): number {
  const observed = t.input + t.cached_read + t.cached_create;
  return observed > 200_000 ? 1_000_000 : 200_000;
}

/**
 * Returns the Phase 4 SessionDetail panel for `sid`, or `null` when the session
 * is unknown to the corpus. Callers MUST treat null as 404 (not 500).
 *
 * `last_assistant` and `open_tool` are placeholders — the HTTP handler in
 * Task 18 overwrites them after running `classify()` on a freshly-tailed
 * transcript. Until that runs, both are empty/null.
 */
export function buildSessionDetail(state: CorpusState, sid: string): SessionDetail | null {
  const s = state.bySession.get(sid);
  if (!s) return null;
  const ageSec = Math.floor((Date.now() - s.startedAtMs) / 1000);
  return {
    sessionId: s.sid,
    cwd: s.cwd,
    repo: basename(s.cwd),
    branch: s.branchTimeline[s.branchTimeline.length - 1]?.branch ?? null,
    branch_history: s.branchTimeline.map((b) => b.branch),
    files_changed: [...s.files.values()].sort((a, b) => b.last_touch - a.last_touch),
    tokens: { ...s.tokens, context_limit: detectContextLimit(s.tokens) },
    load_history: [...s.loadHistory],
    last_assistant: "",       // overwritten by Task 18 HTTP handler via classify()
    open_tool: null,          // overwritten by Task 18 HTTP handler via classify()
    // Defensive copy: decisionsProjection.query returns the LIVE corpus array;
    // returning it directly would let consumers mutate corpus state via .sort()
    // / .splice() / .reverse(), and would also race with the tail watcher's
    // push during JSON serialization. The cost is one shallow copy per request.
    decisions: [...decisionsProjection.query(state, s.cwd)],
    source: "cc",
    age_sec: ageSec,
  };
}
