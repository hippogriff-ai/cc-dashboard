// backend/src/corpus/decisions.ts
// Pure functions over already-loaded transcripts. The tail watcher invokes
// extractDecisions on each session's transcript and merges into state.

import type { DecisionPair } from "./indices.ts";
import type { Turn } from "../claude/transcript.ts";
import { extractText } from "../claude/transcript.ts";

const MAX_REPLY_LEN = 200;

// Sentinel that cannot appear in a real (q, a) pair: \u0000 is illegal in Claude
// transcript text per the JSONL spec. Joining with it makes the dedup key a
// 1:1 function of (q, a), so distinct pairs never collide.
const DEDUP_SEP = "\u0000";

export function extractDecisions(turns: Turn[]): DecisionPair[] {
  const pairs: DecisionPair[] = [];
  for (let i = 0; i < turns.length - 1; i++) {
    const a = turns[i]!;
    const u = turns[i + 1]!;
    if (a.type !== "assistant" || u.type !== "user") continue;
    const aText = extractText(a.message?.content).trim();
    if (!aText.endsWith("?")) continue;
    const lastQuestion = aText.split("\n").reverse().find((l) => l.trim().endsWith("?")) ?? aText;
    const q = lastQuestion.trim().slice(-300);

    const uContent = u.message?.content;
    let reply = "";
    if (typeof uContent === "string") reply = uContent;
    else if (Array.isArray(uContent)) {
      for (const b of uContent) {
        if (b.type === "text" && typeof b.text === "string") { reply = b.text; break; }
      }
    }
    reply = reply.trim();
    if (!reply || reply.length > MAX_REPLY_LEN) continue;
    if (reply.startsWith("<ide_selection>") || reply.startsWith("<system-reminder>")) continue;
    pairs.push({ q, a: reply });
  }
  // Dedupe by raw (q, a) — see DEDUP_SEP above for why a string Set is collision-free.
  const seen = new Set<string>();
  return pairs.filter((p) => {
    const k = p.q + DEDUP_SEP + p.a;
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}
