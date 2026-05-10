// backend/src/actions/resume.ts
import { spawnSync } from "node:child_process";
import type { ResumeResult } from "../types.ts";
import { log } from "../util/log.ts";

function shellQuote(s: string): string {
  return "'" + s.replace(/'/g, `'\\''`) + "'";
}

export function resumeCommand(cwd: string, sid: string | null): ResumeResult {
  const parts = [`cd ${shellQuote(cwd)}`];
  parts.push(sid ? `claude --resume ${sid}` : "claude --continue");
  const cmd = parts.join(" && ");
  const r = spawnSync("pbcopy", [], { input: cmd, timeout: 2000 });
  const copied = r.status === 0;
  if (!copied) {
    log.warn("resumeCommand: pbcopy failed", {
      status: r.status,
      signal: r.signal,
      errorCode: (r.error as NodeJS.ErrnoException | undefined)?.code,
    });
  }
  return { command: cmd, copied_to_clipboard: copied };
}
