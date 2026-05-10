// backend/src/actions/openIde.ts
import { existsSync, statSync } from "node:fs";
import type { OpenIdeResult } from "../types.ts";
import { detectIde } from "../util/ide.ts";
import { spawnSync } from "node:child_process";

export function openInIde(cwd: string): OpenIdeResult {
  if (!cwd || !existsSync(cwd) || !statSync(cwd).isDirectory()) {
    return { ok: false, error: "cwd_not_a_directory" };
  }
  const { bundle, display } = detectIde();
  const openArgs = bundle ? ["-a", bundle, cwd] : [cwd];
  const r = spawnSync("open", openArgs, { encoding: "utf-8", timeout: 3000 });
  if (r.status !== 0) {
    const stderr = (r.stderr ?? "").trim();
    const errMsg = (r.error as NodeJS.ErrnoException | undefined)?.message ?? "";
    const detail = (stderr || errMsg).slice(0, 200);
    return { ok: false, error: "open_failed", ide: display, detail };
  }
  return { ok: true, ide: display };
}
