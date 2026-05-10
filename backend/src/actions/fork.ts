// backend/src/actions/fork.ts
import { spawnSync } from "node:child_process";
import { basename } from "node:path";
import type { ForkResult } from "../types.ts";
import { findTranscript, readJsonlTail } from "../claude/transcript.ts";
import { classify } from "../claude/classify.ts";
import { gitInfo, gitDiffStat } from "../util/git.ts";
import { recentPromptsForCwd } from "../claude/history.ts";
import { log } from "../util/log.ts";

export async function forkSummary(cwd: string, sid: string | null): Promise<ForkResult> {
  const tp = sid ? findTranscript(cwd, sid) : null;
  const turns = tp ? readJsonlTail(tp, 400) : [];
  const meta = classify(turns, false);
  const gi = gitInfo(cwd);
  const prompts = await recentPromptsForCwd(cwd, 5);
  const diff = gitDiffStat(cwd);
  const lines = [
    `# Resuming work in \`${basename(cwd)}\``,
    `**Branch**: ${gi.branch ?? "n/a"}  `,
    `**Uncommitted files**: ${gi.dirty}  `,
    `**Last commit**: ${gi.last_commit ?? "n/a"}`,
    "",
    "## What I was working on (recent prompts)",
    ...prompts.map((p) => `- ${p.display}`),
  ];
  if (meta.last_assistant) {
    lines.push("", "## Claude's last message", "```", meta.last_assistant.slice(0, 1500), "```");
  }
  if (meta.open_tool) {
    lines.push("", "## Open tool at session end", `- ${meta.open_tool.name}`);
  }
  if (diff) {
    lines.push("", "## Git diff stat", "```", diff, "```");
  }
  lines.push("", "Pick up from here — please continue where we left off.");
  const summary = lines.join("\n");
  const r = spawnSync("pbcopy", [], { input: summary, timeout: 2000 });
  const copied = r.status === 0;
  if (!copied) {
    log.warn("forkSummary: pbcopy failed", {
      status: r.status,
      signal: r.signal,
      errorCode: (r.error as NodeJS.ErrnoException | undefined)?.code,
    });
  }
  return { summary, copied_to_clipboard: copied };
}
