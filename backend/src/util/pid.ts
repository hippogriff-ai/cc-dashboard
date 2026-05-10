// backend/src/util/pid.ts
import { spawnSync } from "node:child_process";
import { log } from "./log.ts";

interface PsRow {
  startTime: number;     // unix epoch ms
  stat: string;
  ppid: number;
}

// `ps` can fail in three meaningfully-different ways. Collapsing them into a
// single null return would let a transient `ps` outage (PATH issue, timeout
// under load) silently wipe every live session from the inbox, which is the
// exact silent-failure pattern the project forbids.
type PsResult =
  | { kind: "ok"; row: PsRow }
  | { kind: "missing" }      // ps ran fine and reported "no such pid"
  | { kind: "infra-error" }; // ps itself couldn't run / parse — pid status unknown

function ps(pid: number): PsResult {
  const r = spawnSync("ps", ["-o", "lstart=,stat=,ppid=", "-p", String(pid)], {
    encoding: "utf-8",
    timeout: 1000,
  });
  // r.error is set by spawnSync on ENOENT (ps not on PATH), ETIMEDOUT (1s
  // budget exceeded), or signal kill. None of these mean the inspected pid
  // is dead — they mean we couldn't ask. Surface a distinct sentinel.
  if (r.error) {
    log.warn("ps spawn failed; pid status unknown", { pid, error: r.error.message });
    return { kind: "infra-error" };
  }
  // status===null without r.error shouldn't happen, but treat as infra error.
  if (r.status === null) {
    log.warn("ps returned null status without error; treating as infra error", { pid });
    return { kind: "infra-error" };
  }
  // Non-zero status with empty stdout is the canonical "no such pid" outcome.
  if (r.status !== 0 || !r.stdout) return { kind: "missing" };
  const line = r.stdout.trim();
  if (!line) return { kind: "missing" };
  // lstart is 5 whitespace-separated fields: "Wed Apr 28 10:15:32 2026"
  const parts = line.split(/\s+/);
  if (parts.length < 7) {
    // Format unexpected — log so a future macOS ps change is visible.
    log.warn("ps output had fewer than 7 fields; format may have changed", { pid, line });
    return { kind: "infra-error" };
  }
  const lstart = parts.slice(0, 5).join(" ");
  const stat = parts[5]!;
  const ppid = parseInt(parts[6]!, 10);
  const ts = Date.parse(lstart);
  if (isNaN(ts)) {
    log.warn("ps lstart did not parse as a date", { pid, lstart });
    return { kind: "infra-error" };
  }
  return { kind: "ok", row: { startTime: ts, stat, ppid } };
}

export function getProcessStartTime(pid: number): number | null {
  const r = ps(pid);
  return r.kind === "ok" ? r.row.startTime : null;
}

export function isPidAlive(pid: number, expectedStartTime?: number): boolean {
  // Step 1: probe pid existence cheaply. ESRCH means definitely dead;
  // EPERM (process owned by another user) means alive — we tolerate either
  // success or EPERM as "exists" by deferring the verdict to `ps`.
  try {
    process.kill(pid, 0);
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code !== "EPERM") return false;
  }
  // Step 2: consult ps for status, parent, and start time.
  const r = ps(pid);
  if (r.kind === "missing") return false;
  // On infra error, the kill probe already said the pid exists; preserve the
  // session rather than silently dropping it. The warn log records the issue.
  if (r.kind === "infra-error") return true;
  const row = r.row;
  if (row.stat.includes("T") || row.stat.includes("Z")) return false; // suspended or zombie
  if (row.ppid === 1) return false; // orphaned
  if (expectedStartTime !== undefined) {
    if (Math.abs(row.startTime - expectedStartTime) > 2000) return false; // PID reuse
  }
  return true;
}
