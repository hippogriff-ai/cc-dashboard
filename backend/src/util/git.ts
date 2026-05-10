// backend/src/util/git.ts
import { spawn, spawnSync } from "node:child_process";
import { statSync } from "node:fs";
import { StringDecoder } from "node:string_decoder";
import { log } from "./log.ts";

export interface GitInfo {
  branch: string | null;
  dirty: number;
  last_commit: string | null;
}

// 5-second TTL on cwd → GitInfo. Branch/dirty/last-commit don't change every
// poll cycle, so re-spawning three `git` subprocesses per cwd on every /api/recent,
// every /api/live, every /api/panel, and every transcript watch event was the
// dominant event-loop blocker (see CONTINUITY Loop 26 root-cause analysis).
const TTL_MS = 5_000;
const cache = new Map<string, { ts: number; value: GitInfo }>();
const NULL_GIT: GitInfo = { branch: null, dirty: 0, last_commit: null };

// statSync throws on missing/EACCES paths; the catch covers both. existsSync
// would be a redundant extra syscall on the happy path.
function cwdValid(cwd: string): boolean {
  try {
    return statSync(cwd).isDirectory();
  } catch {
    return false;
  }
}

function parseGitInfo(branchOut: string | null, statusOut: string | null, logOut: string | null): GitInfo {
  const dirty = statusOut ? statusOut.split("\n").filter((l) => l.trim().length > 0).length : 0;
  return {
    branch: branchOut || null,
    dirty,
    last_commit: logOut || null,
  };
}

function runGitSync(cwd: string, args: string[], timeoutMs: number): string | null {
  const r = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf-8", timeout: timeoutMs });
  if (r.status !== 0) return null;
  return r.stdout.trim();
}

function runGitAsync(cwd: string, args: string[], timeoutMs: number): Promise<string | null> {
  return new Promise((resolve) => {
    let resolved = false;
    const finish = (val: string | null): void => {
      if (resolved) return;
      resolved = true;
      clearTimeout(timer);
      // Best-effort kill: child may already be gone (close fired, then this).
      try { child.kill("SIGKILL"); } catch { /* already exited */ }
      resolve(val);
    };
    const child = spawn("git", ["-C", cwd, ...args], { stdio: ["ignore", "pipe", "ignore"] });
    // StringDecoder is chunk-safe for split UTF-8 sequences. A naive `chunk.toString("utf-8")`
    // accumulator silently corrupts non-ASCII branch names / commit messages into U+FFFD when
    // a multibyte sequence straddles a chunk boundary.
    const decoder = new StringDecoder("utf-8");
    let out = "";
    const timer = setTimeout(() => finish(null), timeoutMs);
    child.stdout.on("data", (chunk: Buffer) => { out += decoder.write(chunk); });
    // The Error payload (typically ENOENT for missing `git` or EACCES on cwd) is
    // useful diagnostic signal — surface it once per failure rather than dropping it.
    child.on("error", (e: Error) => {
      log.warn("git: spawn error", {
        cwd,
        args,
        code: (e as NodeJS.ErrnoException).code,
        message: e.message,
      });
      finish(null);
    });
    child.on("close", (code: number | null) => {
      out += decoder.end();
      finish(code === 0 ? out.trim() : null);
    });
  });
}

function readCache(cwd: string, now: number): GitInfo | null {
  const hit = cache.get(cwd);
  if (hit && now - hit.ts < TTL_MS) return hit.value;
  return null;
}

export function gitInfo(cwd: string): GitInfo {
  const now = Date.now();
  const cached = readCache(cwd, now);
  if (cached) return cached;
  // Don't cache a NULL_GIT for missing/inaccessible cwd: a flapping mount
  // would otherwise be pinned to "no git data" for 5s every time it hiccups.
  // Let the next poll re-probe.
  if (!cwdValid(cwd)) return NULL_GIT;
  const branch = runGitSync(cwd, ["branch", "--show-current"], 1500);
  const status = runGitSync(cwd, ["status", "--porcelain"], 1500);
  const last = runGitSync(cwd, ["log", "-1", "--pretty=%h %s"], 1500);
  const value = parseGitInfo(branch, status, last);
  cache.set(cwd, { ts: now, value });
  return value;
}

export async function gitInfoAsync(cwd: string): Promise<GitInfo> {
  const now = Date.now();
  const cached = readCache(cwd, now);
  if (cached) return cached;
  if (!cwdValid(cwd)) return NULL_GIT; // see gitInfo() — no negative caching

  const [branch, status, last] = await Promise.all([
    runGitAsync(cwd, ["branch", "--show-current"], 1500),
    runGitAsync(cwd, ["status", "--porcelain"], 1500),
    runGitAsync(cwd, ["log", "-1", "--pretty=%h %s"], 1500),
  ]);
  const value = parseGitInfo(branch, status, last);
  cache.set(cwd, { ts: now, value });
  return value;
}

export function gitDiffStat(cwd: string): string | null {
  const out = runGitSync(cwd, ["diff", "--stat"], 2000);
  return out && out.length > 0 ? out.slice(0, 2000) : null;
}

// Test-only escape hatch. Underscored to discourage production callers — there
// is no scenario in the running sidecar where the cache should be flushed
// manually (5s TTL handles staleness).
export function _clearGitInfoCache(): void {
  cache.clear();
}
