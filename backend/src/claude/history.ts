// backend/src/claude/history.ts
import { createReadStream, existsSync } from "node:fs";
import { createInterface } from "node:readline";
import { historyFile } from "./paths.ts";

export interface PromptEntry {
  display: string;
  timestamp?: string;
}

export async function recentPromptsForCwd(cwd: string, limit: number): Promise<PromptEntry[]> {
  if (!existsSync(historyFile())) return [];
  const stream = createReadStream(historyFile(), { encoding: "utf-8" });
  const rl = createInterface({ input: stream, crlfDelay: Infinity });
  const matches: PromptEntry[] = [];
  for await (const line of rl) {
    if (!line.trim()) continue;
    let obj: { project?: string; display?: string; timestamp?: string };
    try {
      obj = JSON.parse(line);
    } catch {
      continue;
    }
    if (obj.project === cwd) {
      matches.push({ display: (obj.display ?? "").slice(0, 400), timestamp: obj.timestamp });
    }
  }
  return matches.slice(-limit).reverse();
}
