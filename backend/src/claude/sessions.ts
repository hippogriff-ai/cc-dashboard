// backend/src/claude/sessions.ts
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { basename, join } from "node:path";
import type { LiveSession } from "../types.ts";
import { sessionsDir } from "./paths.ts";
import { findTranscript, readJsonlTail } from "./transcript.ts";
import { classify, stalenessDecay } from "./classify.ts";
import { gitInfo } from "../util/git.ts";
import { isPidAlive } from "../util/pid.ts";

interface SessionFile {
  kind?: string;
  pid?: number;
  pidStartTime?: number;
  sessionId?: string;
  cwd?: string;
  startedAt?: number;
}

export function loadLiveSessions(): LiveSession[] {
  const dir = sessionsDir();
  if (!existsSync(dir)) return [];
  const out: LiveSession[] = [];
  for (const name of readdirSync(dir)) {
    if (!name.endsWith(".json")) continue;
    let data: SessionFile;
    try {
      data = JSON.parse(readFileSync(join(dir, name), "utf-8")) as SessionFile;
    } catch {
      continue;
    }
    if (data.kind !== "interactive") continue;
    const pid = data.pid;
    const sid = data.sessionId;
    const cwd = data.cwd ?? "";
    const startedAt = data.startedAt ?? 0;
    if (!pid || !sid) continue;
    // Skip malformed session files lacking cwd: gitInfo("") would silently
    // return all-null and basename("") would yield "", masking the bad entry.
    if (!cwd) continue;
    if (!isPidAlive(pid, data.pidStartTime)) continue;

    const tp = findTranscript(cwd, sid);
    const transcript = tp ? readJsonlTail(tp, 300) : [];
    const meta = classify(transcript, true);
    const gi = gitInfo(cwd);
    // TOCTOU-safe stat: the transcript file can be unlinked between
    // findTranscript and statSync. Falling back to startedAt is preferable
    // to throwing, which would drop every session enumerated after this one.
    let tpMtime = startedAt / 1000;
    if (tp) {
      try {
        tpMtime = statSync(tp).mtimeMs / 1000;
      } catch {
        // file vanished between existsSync and stat; keep startedAt fallback.
      }
    }
    const ageSec = Math.max(0, Date.now() / 1000 - tpMtime);
    const decay = stalenessDecay(ageSec);
    out.push({
      pid,
      sessionId: sid,
      cwd,
      repo: basename(cwd),
      branch: gi.branch,
      dirty: gi.dirty,
      started_at: startedAt,
      last_activity: tpMtime * 1000,
      age_sec: Math.floor(ageSec),
      stale_decay: decay,
      transcript_found: tp !== null,
      ...meta,
      priority: meta.priority + decay,
    });
  }
  out.sort((a, b) => a.priority - b.priority || b.last_activity - a.last_activity);
  return out;
}
