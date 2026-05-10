// backend/src/claude/classify.ts
import type { ClassifyResult, Event, OpenTool } from "../types.ts";
import { extractText, lastTurns, type Turn } from "./transcript.ts";

// All phrases require a first-person verb so we don't false-positive on assistant
// prose like "It would be okay to revert if needed, but should we try the patch?"
// (where "okay to" is descriptive, not a permission ask).
const PERMISSION_PHRASES = [
  /\bcan i (run|use|execute)\b/i,
  /\bmay i (run|use|execute)\b/i,
  /\bok(?:ay)? (?:to (?:run|use|execute|delete|remove|push|drop)|if i)\b/i,
  /\b(?:should i|shall i) (?:run|push|delete|remove|drop)\b/i,
];

function isPermissionPrompt(text: string): boolean {
  if (!text.trim().endsWith("?")) return false;
  return PERMISSION_PHRASES.some((re) => re.test(text));
}

export function classify(transcript: Turn[], alive: boolean): ClassifyResult {
  const turns = lastTurns(transcript, 20);

  // Side-panel context fields (most recent of each, regardless of last-turn classification).
  // Note: tool_result blocks on user turns are intentionally skipped — they are tool
  // plumbing, not human prompts, so `last_user` should keep the most recent real text.
  let lastUserText = "";
  let lastAssistantText = "";
  for (const t of turns) {
    const m = t.message;
    if (!m) continue;
    if (m.role === "user") {
      if (typeof m.content === "string") lastUserText = m.content;
      else if (Array.isArray(m.content)) {
        const txts = m.content.flatMap((b) => (b.type === "text" && typeof b.text === "string" ? [b.text] : []));
        if (txts.length) lastUserText = txts.join("\n");
      }
    } else if (m.role === "assistant") {
      const text = extractText(m.content);
      if (text) lastAssistantText = text;
    }
  }

  if (turns.length === 0) {
    return {
      event: "CLEAR",
      reason: "",
      priority: 99,
      last_user: "",
      last_assistant: "",
      open_tool: null,
    };
  }

  const last = turns[turns.length - 1]!;
  const m = last.message ?? {};
  const role = m.role;
  const content = m.content;

  let event: Event = "CLEAR";
  let reason = "";
  let priority = 99;
  let openTool: OpenTool | null = null;

  if (role === "assistant") {
    let hasOpenTool = false;
    const textParts: string[] = [];
    if (Array.isArray(content)) {
      for (const b of content) {
        if (b.type === "tool_use") {
          hasOpenTool = true;
          openTool = { name: b.name ?? "?", id: b.id };
        } else if (b.type === "text" && typeof b.text === "string") {
          textParts.push(b.text);
        }
      }
    } else if (typeof content === "string") {
      textParts.push(content);
    }
    const text = textParts.join("\n").trim();

    if (hasOpenTool && alive) {
      event = "WORKING";
      reason = `running ${openTool?.name ?? "tool"}`;
      priority = 90;
    } else {
      // Outside the WORKING branch the tool is no longer "open" — clear it so
      // the row doesn't render a stale tool name on a dead session.
      openTool = null;
      if (text && isPermissionPrompt(text)) {
        event = "PERMISSION_PENDING";
        reason = text.split("\n").pop()!.slice(0, 180);
        priority = 5;
      } else if (text && text.trim().endsWith("?")) {
        event = "ASK";
        reason = text.split("\n").pop()!.slice(0, 180);
        priority = 20;
      } else {
        event = "IDLE_AFTER_COMPLETE";
        reason = "ready for next instruction";
        priority = 40;
      }
    }
  } else if (role === "user") {
    let isError = false;
    let detail = "";
    if (Array.isArray(content)) {
      for (const b of content) {
        if (b.type === "tool_result" && b.is_error) {
          isError = true;
          if (typeof b.content === "string") detail = b.content.slice(0, 200);
          else if (Array.isArray(b.content)) {
            detail = b.content
              .map((x: unknown) =>
                x && typeof x === "object" && "text" in (x as object) ? (x as { text?: string }).text ?? "" : "",
              )
              .join(" ")
              .slice(0, 200);
          }
          break;
        }
      }
    }
    if (isError) {
      event = "TOOL_FAILED";
      // If the error result had only non-text blocks (e.g. image-only), surface
      // a marker so the UI shows "tool failed but no message" instead of a
      // misleadingly empty error.
      const display = detail.length > 0 ? detail : "<no text in error result>";
      reason = `tool error: ${display.slice(0, 100)}`;
      priority = 10;
    } else {
      event = alive ? "WORKING" : "CLEAR";
      reason = "processing...";
      priority = alive ? 85 : 99;
    }
  }

  return {
    event,
    reason,
    priority,
    last_user: lastUserText.slice(0, 400),
    last_assistant: lastAssistantText.slice(0, 800),
    open_tool: openTool,
  };
}

export function stalenessDecay(ageSec: number): number {
  if (ageSec <= 300) return 0;
  return Math.min(60, Math.floor((ageSec - 300) / 360));
}
