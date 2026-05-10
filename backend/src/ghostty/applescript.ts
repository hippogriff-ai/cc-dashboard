import { spawnSync, type SpawnSyncReturns } from "node:child_process";

export interface GhosttyWindow { index: number; title: string }
export interface ListResult { windows: GhosttyWindow[]; error: string | null }

const LIST_SCRIPT = `
tell application "System Events"
  tell process "Ghostty"
    set out to ""
    set n to count of windows
    repeat with i from 1 to n
      try
        set t to name of window i
      on error
        set t to ""
      end try
      set out to out & i & "\\t" & t & linefeed
    end repeat
    return out
  end tell
end tell`;

// spawnSync sets r.error and leaves r.status as null when the binary itself
// fails to launch (ENOENT for missing osascript, e.g. on Linux/Windows hosts)
// or when the timeout fires. Without distinguishing this from a genuine
// non-zero AppleScript error, callers conflate "macOS not available" with
// "Ghostty refused" — and `r.stderr.trim()` would crash on `undefined`.
function classifySpawnError(r: SpawnSyncReturns<string>): { reason: string; detail: string } | null {
  if (!r.error) return null;
  const code = (r.error as NodeJS.ErrnoException).code ?? "";
  if (code === "ENOENT") {
    return { reason: "osascript_unavailable", detail: "osascript not found on PATH (cc-dashboard requires macOS)" };
  }
  if (code === "ETIMEDOUT") {
    return { reason: "osascript_timeout", detail: r.error.message };
  }
  return { reason: "osascript_spawn_failed", detail: r.error.message };
}

export function activateGhostty(): { ok: boolean; reason?: string; detail?: string } {
  const r = spawnSync("osascript", ["-e", 'tell application "Ghostty" to activate'], { encoding: "utf-8", timeout: 2000 });
  const spawnErr = classifySpawnError(r);
  if (spawnErr) return { ok: false, ...spawnErr };
  if (r.status !== 0) {
    return { ok: false, reason: "ghostty_activate_failed", detail: (r.stderr ?? "").trim().slice(0, 200) };
  }
  return { ok: true };
}

export function listGhosttyWindows(): ListResult {
  const r = spawnSync("osascript", ["-e", LIST_SCRIPT], { encoding: "utf-8", timeout: 3000 });
  const spawnErr = classifySpawnError(r);
  if (spawnErr) return { windows: [], error: `${spawnErr.reason}: ${spawnErr.detail.slice(0, 200)}` };
  if (r.status !== 0) {
    // Guard `r.stderr` — even on non-spawn errors it can be undefined for non-string returns.
    const stderr = (r.stderr ?? "").trim();
    const err = stderr || `exit ${r.status}`;
    const reason = err.includes("1002") || err.toLowerCase().includes("not allowed") ? "ax_permission_denied" : "list_failed";
    return { windows: [], error: `${reason}: ${err.slice(0, 200)}` };
  }
  const windows: GhosttyWindow[] = [];
  for (const line of (r.stdout ?? "").split("\n")) {
    if (!line.includes("\t")) continue;
    const [idxs, title] = line.split("\t", 2) as [string, string];
    const idx = parseInt(idxs.trim(), 10);
    if (!isNaN(idx)) windows.push({ index: idx, title: title.trim() });
  }
  return { windows, error: null };
}

export function raiseGhosttyWindow(index: number): boolean {
  const script = `
tell application "System Events"
  tell process "Ghostty"
    try
      perform action "AXRaise" of window ${index}
      set frontmost to true
      return "ok"
    on error
      return "err"
    end try
  end tell
end tell`;
  const r = spawnSync("osascript", ["-e", script], { encoding: "utf-8", timeout: 2000 });
  // On spawn failure, stdout is undefined; treat as "not raised".
  // The activate/list path already surfaced the user-visible error first.
  return (r.stdout ?? "").includes("ok");
}
