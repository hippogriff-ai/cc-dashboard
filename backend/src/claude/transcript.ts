// backend/src/claude/transcript.ts
import { existsSync, statSync, openSync, readSync, closeSync } from "node:fs";
import { join } from "node:path";
import { projectsDir, cwdToEncoded } from "./paths.ts";
import { log } from "../util/log.ts";

export interface TurnContentBlock {
  type: string;
  text?: string;
  name?: string;
  id?: string;
  is_error?: boolean;
  content?: unknown;
  input?: unknown;
}
export interface TurnMessage {
  role?: string;
  content?: string | TurnContentBlock[];
  usage?: {
    input_tokens?: number;
    cache_creation_input_tokens?: number;
    cache_read_input_tokens?: number;
    output_tokens?: number;
  };
}
export interface Turn {
  type?: string;
  cwd?: string;
  isSidechain?: boolean;
  message?: TurnMessage;
  timestamp?: string;
  uuid?: string;
}

export function findTranscript(cwd: string, sid: string): string | null {
  const direct = join(projectsDir(), cwdToEncoded(cwd), `${sid}.jsonl`);
  if (existsSync(direct)) return direct;
  return null;
}

export function readJsonlTail(path: string, n: number): Turn[] {
  if (!existsSync(path)) return [];
  let data: string;
  let chunkedFromMiddle = false;
  try {
    const size = statSync(path).size;
    if (size === 0) return [];
    const chunk = Math.min(size, 256 * 1024);
    chunkedFromMiddle = chunk < size;
    const fd = openSync(path, "r");
    try {
      const buf = Buffer.alloc(chunk);
      const bytesRead = readSync(fd, buf, 0, chunk, size - chunk);
      data = buf.subarray(0, bytesRead).toString("utf-8");
    } finally {
      closeSync(fd);
    }
  } catch (err) {
    // Outer catch: file disappeared between existsSync and read (TOCTOU),
    // or stat/open/read failed unexpectedly. Rare; log so operators can spot it.
    const message = err instanceof Error ? err.message : String(err);
    log.warn("readJsonlTail: read failed; returning empty", { path, message });
    return [];
  }
  let lines = data.split("\n").filter((l) => l.trim().length > 0);
  // When chunked from the middle of a large file, the first line is partial
  // (and may also start mid-UTF-8-codepoint). Discard it to avoid corrupted parses.
  if (chunkedFromMiddle && lines.length > 0) {
    lines = lines.slice(1);
  }
  const out: Turn[] = [];
  for (const line of lines.slice(-n)) {
    try {
      out.push(JSON.parse(line) as Turn);
    } catch {
      // Inner catch: jsonl tail can have a partially-written final line during
      // live tailing — this is normal and frequent, so silent-skip is the contract.
    }
  }
  return out;
}

export function lastTurns(transcript: Turn[], k: number): Turn[] {
  return transcript
    .filter((t) =>
      (t.type === "user" || t.type === "assistant") &&
      !t.isSidechain &&
      t.message != null &&
      typeof t.message === "object",
    )
    .slice(-k);
}

export function extractText(content: string | TurnContentBlock[] | undefined): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  const parts: string[] = [];
  for (const block of content) {
    if (block.type === "text" && typeof block.text === "string") parts.push(block.text);
    else if (block.type === "tool_use") parts.push(`[tool: ${block.name ?? "?"}]`);
  }
  return parts.join("\n");
}
