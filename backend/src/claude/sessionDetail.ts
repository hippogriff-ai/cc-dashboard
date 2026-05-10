// backend/src/claude/sessionDetail.ts
import { basename } from "node:path";
import type { SessionDetail } from "../types.ts";
import type { CorpusState } from "../corpus/indices.ts";
import { decisionsProjection } from "../corpus/projections.ts";

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
    tokens: { ...s.tokens, context_limit: 200_000 },
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
