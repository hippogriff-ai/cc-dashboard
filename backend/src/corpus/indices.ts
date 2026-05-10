// backend/src/corpus/indices.ts
// Per-session and per-cwd in-memory indices, populated by the tail watcher.

export interface FileTouch { path: string; edits: number; last_touch: number }
export interface BranchSample { ts: number; branch: string }
export interface SessionTokens { input: number; cached_read: number; cached_create: number; output: number }
export interface DecisionPair { q: string; a: string }

export interface SessionIndex {
  sid: string;
  cwd: string;
  files: Map<string, FileTouch>;
  branchTimeline: BranchSample[];          // dedup consecutive same-branch
  tokens: SessionTokens;
  loadHistory: number[];                   // tool_use count per minute, length 32
  loadStartMs: number;                     // anchor for the rolling window
  startedAtMs: number;
  endedAtMs?: number;
}

export interface CorpusState {
  bySession: Map<string, SessionIndex>;     // key = sid
  decisionsByCwd: Map<string, DecisionPair[]>; // deduped
}

export function emptyState(): CorpusState {
  return { bySession: new Map(), decisionsByCwd: new Map() };
}

export function getOrCreateSession(state: CorpusState, sid: string, cwd: string): SessionIndex {
  let s = state.bySession.get(sid);
  if (!s) {
    // loadStartMs / startedAtMs default to creation time as a placeholder. The
    // tail watcher (Task 16) overwrites startedAtMs from the transcript's first
    // turn timestamp before any consumer reads it. Do NOT rely on these defaults
    // outside the watcher's cold-start path.
    s = {
      sid, cwd,
      files: new Map(),
      branchTimeline: [],
      tokens: { input: 0, cached_read: 0, cached_create: 0, output: 0 },
      loadHistory: new Array(32).fill(0),
      loadStartMs: Date.now(),
      startedAtMs: Date.now(),
    };
    state.bySession.set(sid, s);
  }
  return s;
}
