// backend/src/claude/panel.ts
import { basename } from "node:path";
import type { Panel } from "../types.ts";
import { findTranscript, readJsonlTail } from "./transcript.ts";
import { classify } from "./classify.ts";
import { gitInfo, gitDiffStat } from "../util/git.ts";
import { recentPromptsForCwd } from "./history.ts";
import { log } from "../util/log.ts";

export async function buildPanel(cwd: string, sid: string | null, alive: boolean): Promise<Panel> {
  const tp = sid ? findTranscript(cwd, sid) : null;
  const turns = tp ? readJsonlTail(tp, 400) : [];
  // `alive` controls how classify resolves an in-flight assistant turn (WORKING vs.
  // IDLE_AFTER_COMPLETE) and whether a trailing user turn is WORKING vs. CLEAR. The
  // Live tab passes `alive=true` for sessions whose pid is still kicking; Restore
  // passes `alive=false`. Plan-verbatim hardcoded false — wrong for the Live tab.
  const meta = classify(turns, alive);
  const gi = gitInfo(cwd);
  // recent_prompts is auxiliary metadata; a history.jsonl read failure must not
  // take down the whole panel. Log and degrade to an empty list.
  let prompts: Awaited<ReturnType<typeof recentPromptsForCwd>> = [];
  try {
    prompts = await recentPromptsForCwd(cwd, 5);
  } catch (e) {
    log.warn("buildPanel: recentPromptsForCwd failed; degrading to empty list", {
      cwd, error: e instanceof Error ? e.message : String(e),
    });
  }
  return {
    cwd, repo: basename(cwd), sessionId: sid,
    transcript_found: tp !== null,
    git: gi,
    diff_summary: gitDiffStat(cwd),
    recent_prompts: prompts,
    last_user: meta.last_user, last_assistant: meta.last_assistant,
    event: meta.event, reason: meta.reason, open_tool: meta.open_tool,
  };
}
