// backend/src/claude/recent.ts
import { existsSync, readdirSync, statSync, openSync, readSync, closeSync } from "node:fs";
import { basename, join } from "node:path";
import type { RecentRepo } from "../types.ts";
import { projectsDir } from "./paths.ts";
import { readJsonlTail } from "./transcript.ts";
import { classify } from "./classify.ts";
import { gitInfoAsync } from "../util/git.ts";

// Anchored to the start of the encoded directory name. Encoded names always
// begin with `-` (cwdToEncoded prepends nothing; an absolute path's leading
// `/` becomes `-`). Without anchoring, `/test-repo/` matched any encoded name
// containing `test-repo` — silently dropping legitimate user repos like
// `~/work/my-test-repo-tools` (encoded as `-Users-foo-work-my-test-repo-tools`).
const SKIP_PATTERNS = [/^-private-var-folders-/, /^-test-repo(-|$)/];

function firstCwd(jsonlPath: string): string | null {
  try {
    const fd = openSync(jsonlPath, "r");
    try {
      const buf = Buffer.alloc(64 * 1024);
      const n = readSync(fd, buf, 0, buf.length, 0);
      const text = buf.subarray(0, n).toString("utf-8");
      for (const line of text.split("\n")) {
        if (!line.trim()) continue;
        try {
          const obj = JSON.parse(line) as { cwd?: string };
          if (obj.cwd) return obj.cwd;
        } catch {
          // skip
        }
      }
      return null;
    } finally {
      closeSync(fd);
    }
  } catch {
    return null;
  }
}

export async function loadRecentByRepo(days: number): Promise<RecentRepo[]> {
  if (!existsSync(projectsDir())) return [];
  const cutoff = Date.now() / 1000 - days * 86400;
  const byCwd = new Map<string, { mtime: number; sessionId: string; transcript: string }>();
  for (const dirent of readdirSync(projectsDir(), { withFileTypes: true })) {
    if (!dirent.isDirectory()) continue;
    const name = dirent.name;
    if (SKIP_PATTERNS.some((re) => re.test(name))) continue;
    const dirPath = join(projectsDir(), name);
    for (const entry of readdirSync(dirPath)) {
      if (!entry.endsWith(".jsonl")) continue;
      const file = join(dirPath, entry);
      let mt: number;
      try {
        mt = statSync(file).mtimeMs / 1000;
      } catch {
        continue;
      }
      if (mt < cutoff) continue;
      // Skip the row entirely if firstCwd returned null. The plan's reverse-
      // encode fallback (`name.replace(/^-/,"").replace(/-/g,"/")`) is lossy:
      // both `/` and `.` encode to `-`, so `-foo-bar-baz` could decode to
      // `/foo/bar/baz` OR `/foo.bar/baz` etc. If a directory at the mangled
      // path happens to exist, the row would surface against a wrong repo
      // silently. Better to drop the row than to publish wrong data.
      const cwd = firstCwd(file);
      if (!cwd) continue;
      const sid = entry.replace(/\.jsonl$/, "");
      const cur = byCwd.get(cwd);
      if (!cur || mt > cur.mtime) byCwd.set(cwd, { mtime: mt, sessionId: sid, transcript: file });
    }
  }
  // Materialize candidates that survive the cwd-existence check, then probe git
  // in parallel. Was: N × 3 × spawnSync(timeout=1500ms) serial, blocking the event
  // loop for up to 4.5s per cwd. Now: O(slowest single cwd); the loop stays free
  // to service /api/health and SIGTERM mid-flight.
  const candidates: Array<{ cwd: string; mtime: number; sessionId: string; transcript: string }> = [];
  for (const [cwd, info] of byCwd.entries()) {
    if (!existsSync(cwd)) continue;
    candidates.push({ cwd, ...info });
  }
  const rows: RecentRepo[] = await Promise.all(candidates.map(async (c) => {
    const gi = await gitInfoAsync(c.cwd);
    const transcript = readJsonlTail(c.transcript, 300);
    const meta = classify(transcript, false);
    return {
      cwd: c.cwd,
      repo: basename(c.cwd),
      branch: gi.branch,
      dirty: gi.dirty,
      last_commit: gi.last_commit,
      sessionId: c.sessionId,
      last_activity: c.mtime * 1000,
      ...meta,
    };
  }));
  rows.sort((a, b) => b.last_activity - a.last_activity);
  return rows;
}
