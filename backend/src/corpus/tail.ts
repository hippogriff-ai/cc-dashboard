// backend/src/corpus/tail.ts
// Minimal tail watcher: subscribe to per-session-jsonl mutation events
// and incrementally update CorpusState. Cold-start: full read.

import {
  existsSync,
  statSync,
  openSync,
  readSync,
  closeSync,
  watch as fsWatch,
  type FSWatcher,
} from "node:fs";
import type { Turn } from "../claude/transcript.ts";
import type { CorpusState, FileTouch } from "./indices.ts";
import { getOrCreateSession } from "./indices.ts";
import { extractDecisions } from "./decisions.ts";
import { gitInfo } from "../util/git.ts";
import { log } from "../util/log.ts";

// Same separator as decisions.ts dedup — \u0000 cannot appear in transcript text.
const DEDUP_SEP = "\u0000";

export interface TailHandle {
  state: CorpusState;
  watchers: Map<string, FSWatcher>;
  offsets: Map<string, number>;
  add(sid: string, cwd: string, transcriptPath: string): void;
  remove(sid: string): void;
  closeAll(): void;
}

function readFromOffset(path: string, offset: number): { lines: string[]; newOffset: number } {
  // Preserve last-known offset on transient absence (rotation / atomic-rename writers).
  // Returning 0 here would cause the next watch event to re-read the file from byte 0
  // and double-count tokens / file-edits / load-history (those accumulators are not
  // dedupe-protected the way decisionsByCwd is).
  if (!existsSync(path)) {
    log.warn("tail: transcript missing on read; preserving offset", { path, offset });
    return { lines: [], newOffset: offset };
  }
  const size = statSync(path).size;
  // If the file shrank (truncated/rotated), reset to its new size; do NOT re-read from 0
  // because applyTurns is not idempotent for token/edit accumulators.
  if (size < offset) {
    log.warn("tail: transcript shrank; resetting offset to current size", { path, offset, size });
    return { lines: [], newOffset: size };
  }
  if (size === offset) return { lines: [], newOffset: size };
  const buf = Buffer.alloc(size - offset);
  const fd = openSync(path, "r");
  try {
    readSync(fd, buf, 0, buf.length, offset);
  } finally {
    closeSync(fd);
  }
  const text = buf.toString("utf-8");
  const lines = text.split("\n").filter((l) => l.trim().length > 0);
  return { lines, newOffset: size };
}

function applyTurns(
  state: CorpusState,
  sid: string,
  cwd: string,
  turns: Turn[],
): void {
  const sess = getOrCreateSession(state, sid, cwd);

  // Order is load-bearing: accumulate tokens / files / load FIRST so a
  // transient failure in the optional side-effects below (gitInfo subprocess
  // glitches; extractDecisions regex misbehaviour) can't strand a session
  // with zero tokens forever. Pre-fix, an exception in gitInfo (which runs
  // a git subprocess and can throw on lock files / EAGAIN / permission
  // races) would propagate out of applyTurns → tail.add's catch sets
  // coldStartFailed=true → watcher never registers → rebalance retries
  // every 5s but throws the same way each retry, so the bySession entry
  // (already created by getOrCreateSession above) is permanently stuck at
  // tokens=0. Observed in the wild: gbrain session showed 0/200K for 23h
  // while its transcript had cumulative 35M cache_read tokens; backend
  // restart cleared the bad state. Tokens-first ordering is the fix.

  // Files + tokens + load
  for (const t of turns) {
    if (t.type !== "assistant") continue;
    const m = t.message;
    if (!m) continue;
    if (m.usage) {
      sess.tokens.input += m.usage.input_tokens ?? 0;
      sess.tokens.cached_read += m.usage.cache_read_input_tokens ?? 0;
      sess.tokens.cached_create += m.usage.cache_creation_input_tokens ?? 0;
      sess.tokens.output += m.usage.output_tokens ?? 0;
    }
    if (Array.isArray(m.content)) {
      for (const b of m.content) {
        if (b.type === "tool_use") {
          // Bump the most recent bucket. NOTE: time-based rotation (one bucket per
          // minute, dropping the oldest) is owned by a future tick mechanism — see
          // plan Task 18 (HTTP server poll cycle) or Task 17 (panel builder).
          // Until that lands, all tool_use counts pile into [length-1] and the array
          // behaves as a single counter. Consumers must treat unrotated history as
          // "session-total tool calls", not "last 32 minutes".
          const lastIdx = sess.loadHistory.length - 1;
          sess.loadHistory[lastIdx] = (sess.loadHistory[lastIdx] ?? 0) + 1;
          // File-touch tracking: pull a path from common tool inputs
          const inp = (b.input ?? {}) as Record<string, unknown>;
          const path = (typeof inp.file_path === "string" ? inp.file_path : null)
            ?? (typeof inp.notebook_path === "string" ? inp.notebook_path : null);
          if (path && (b.name === "Edit" || b.name === "Write" || b.name === "MultiEdit" || b.name === "NotebookEdit")) {
            const ft: FileTouch = sess.files.get(path) ?? { path, edits: 0, last_touch: 0 };
            ft.edits += 1;
            ft.last_touch = Date.now();
            sess.files.set(path, ft);
          }
        }
      }
    }
  }

  // Branch + decisions are side-effect-only; their failures don't justify
  // dropping the token accumulation we just did. Catch + log so transient
  // git or regex glitches degrade gracefully into "no branch update this
  // tick" rather than "session permanently stuck at zero tokens".
  try {
    const gi = gitInfo(cwd);
    if (gi.branch) {
      const last = sess.branchTimeline[sess.branchTimeline.length - 1];
      if (!last || last.branch !== gi.branch) {
        sess.branchTimeline.push({ ts: Date.now(), branch: gi.branch });
      }
    }
  } catch (e) {
    log.warn("applyTurns: gitInfo failed; skipping branch update", {
      sid, cwd, error: e instanceof Error ? e.message : String(e),
    });
  }

  // Decisions per cwd: extractDecisions is idempotent (it dedupes internally),
  // and we additionally dedupe against existing pairs to avoid re-pushing on every event.
  try {
    const pairs = extractDecisions(turns);
    if (pairs.length) {
      const cur = state.decisionsByCwd.get(cwd) ?? [];
      const seen = new Set(cur.map((p) => p.q + DEDUP_SEP + p.a));
      for (const p of pairs) {
        const k = p.q + DEDUP_SEP + p.a;
        if (!seen.has(k)) { cur.push(p); seen.add(k); }
      }
      state.decisionsByCwd.set(cwd, cur);
    }
  } catch (e) {
    log.warn("applyTurns: extractDecisions failed; skipping decision update", {
      sid, cwd, error: e instanceof Error ? e.message : String(e),
    });
  }
}

export function createTail(state: CorpusState): TailHandle {
  const watchers = new Map<string, FSWatcher>();
  const offsets = new Map<string, number>();

  function add(sid: string, cwd: string, transcriptPath: string): void {
    if (watchers.has(sid)) return;
    // Cold start: snapshot size FIRST, read exactly that many bytes, set offset = size.
    // Reading-then-stat (or stat-then-readFileSync) leaves a TOCTOU window: if a writer
    // appends between the two syscalls, those bytes get applied at cold-start AND get
    // re-read on the first watch event because offset = post-append size. Tokens and
    // edits would silently double. Bounding the read to the snapshotted size closes that.
    let coldStartFailed = false;
    if (existsSync(transcriptPath)) {
      try {
        const size = statSync(transcriptPath).size;
        let text = "";
        if (size > 0) {
          const buf = Buffer.alloc(size);
          const fd = openSync(transcriptPath, "r");
          try {
            const bytesRead = readSync(fd, buf, 0, size, 0);
            text = buf.subarray(0, bytesRead).toString("utf-8");
          } finally {
            closeSync(fd);
          }
        }
        const turns: Turn[] = [];
        for (const line of text.split("\n")) {
          if (!line.trim()) continue;
          try { turns.push(JSON.parse(line) as Turn); } catch { /* partial / corrupt line — skip */ }
        }
        applyTurns(state, sid, cwd, turns);
        // Backfill startedAtMs from the earliest turn timestamp so SessionDetail.age_sec
        // reflects the actual session age, not the sidecar's observation age. Honors the
        // Loop 9 deviation 24 promise. If no turn has a parsable timestamp, leave the
        // creation-time default in place.
        const sess = state.bySession.get(sid);
        if (sess) {
          let earliestMs = Number.POSITIVE_INFINITY;
          for (const t of turns) {
            if (typeof t.timestamp !== "string") continue;
            const ms = Date.parse(t.timestamp);
            if (Number.isFinite(ms) && ms < earliestMs) earliestMs = ms;
          }
          if (Number.isFinite(earliestMs)) sess.startedAtMs = earliestMs;
        }
        offsets.set(sid, size);
      } catch (e) {
        log.warn("tail: cold-read failed; aborting add to avoid double-count on next event", {
          sid, error: e instanceof Error ? e.message : String(e),
        });
        coldStartFailed = true;
      }
    } else {
      offsets.set(sid, 0);
    }
    // If cold-read threw, do NOT register the watcher: a subsequent event would call
    // readFromOffset(path, 0) and re-apply every existing turn, double-counting accumulators.
    // The caller (sessions enumerator) will retry add() on the next poll cycle.
    if (coldStartFailed) return;
    try {
      const w = fsWatch(transcriptPath, { persistent: true }, () => {
        const off = offsets.get(sid) ?? 0;
        const { lines, newOffset } = readFromOffset(transcriptPath, off);
        offsets.set(sid, newOffset);
        const turns: Turn[] = [];
        for (const line of lines) {
          try { turns.push(JSON.parse(line) as Turn); } catch { /* partial line — skip */ }
        }
        if (turns.length) applyTurns(state, sid, cwd, turns);
      });
      watchers.set(sid, w);
    } catch (e) {
      log.warn("tail: watch failed", { sid, error: e instanceof Error ? e.message : String(e) });
    }
  }

  function remove(sid: string): void {
    const w = watchers.get(sid);
    if (w) { w.close(); watchers.delete(sid); }
    offsets.delete(sid);
    // Eviction: keep state for 1h after end so the UI can still show the row, then drop.
    const t = setTimeout(() => state.bySession.delete(sid), 60 * 60 * 1000);
    t.unref?.();
  }

  function closeAll(): void {
    for (const w of watchers.values()) w.close();
    watchers.clear();
    offsets.clear();
  }

  return { state, watchers, offsets, add, remove, closeAll };
}
