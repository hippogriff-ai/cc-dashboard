import { basename } from "node:path";
import { existsSync, readFileSync } from "node:fs";
import type { FocusResult } from "../types.ts";
import { findTranscript } from "../claude/transcript.ts";
import { tokenize } from "./tokenize.ts";
import { scoreWindow } from "./score.ts";
import { activateGhostty, listGhosttyWindows, raiseGhosttyWindow } from "./applescript.ts";

const MIN_SCORE = 5;
const MIN_MARGIN = 3;

function sessionPrompts(cwd: string, sid: string | null): { early: string[]; recent: string[] } {
  if (!sid) return { early: [], recent: [] };
  const tp = findTranscript(cwd, sid);
  if (!tp || !existsSync(tp)) return { early: [], recent: [] };
  const all: string[] = [];
  for (const line of readFileSync(tp, "utf-8").split("\n")) {
    if (!line.includes('"type":"user"')) continue;
    let obj: { isSidechain?: boolean; message?: { role?: string; content?: unknown } };
    try { obj = JSON.parse(line); } catch { continue; }
    if (obj.isSidechain) continue;
    const m = obj.message;
    if (!m || m.role !== "user") continue;
    let text = "";
    if (typeof m.content === "string") text = m.content;
    else if (Array.isArray(m.content)) {
      for (const b of m.content as { type?: string; text?: string }[]) {
        if (b.type === "text" && typeof b.text === "string") { text = b.text; break; }
      }
    }
    if (!text) continue;
    if (text.startsWith("<ide_selection>") || text.startsWith("<system-reminder>")) continue;
    text = text.trim();
    if (text) all.push(text.slice(0, 500));
  }
  return { early: all.slice(0, 5), recent: all.length > 5 ? all.slice(-3) : [] };
}

export async function focusGhostty(cwd: string, sid: string | null): Promise<FocusResult> {
  const { early, recent } = sessionPrompts(cwd, sid);
  const earlyTokens = tokenize(early.join(" "));
  const recentTokens = tokenize(recent.join(" "));
  const cwdTokens = tokenize(basename(cwd).replace(/[-_]/g, " "));

  const act = activateGhostty();
  if (!act.ok) return { ok: false, matched: false, reason: act.reason, detail: act.detail };

  await new Promise((r) => setTimeout(r, 250)); // let AX catch up
  const list = listGhosttyWindows();
  if (list.error) return { ok: false, matched: false, reason: list.error.split(":", 1)[0], detail: list.error };

  const scored = list.windows.map((w) => {
    const tt = tokenize(w.title);
    const s = scoreWindow(tt, earlyTokens, recentTokens, cwdTokens);
    return { ...w, ...s };
  }).sort((a, b) => b.score - a.score);

  const best = scored[0];
  const second = scored[1]?.score ?? 0;
  const confident = best && best.score >= MIN_SCORE && best.score - second >= MIN_MARGIN;

  if (confident) {
    const raised = raiseGhosttyWindow(best.index);
    return {
      ok: true,
      matched: raised,
      window_index: best.index,
      matched_title: best.title,
      score: best.score,
      margin: best.score - second,
    };
  }
  return { ok: true, matched: false, reason: "no_confident_match" };
}
