// backend/src/claude/paths.ts
import { homedir } from "node:os";
import { join } from "node:path";

export function claudeHome(): string {
  return process.env.CLAUDE_HOME ?? join(homedir(), ".claude");
}

export function sessionsDir(): string {
  return join(claudeHome(), "sessions");
}

export function projectsDir(): string {
  return join(claudeHome(), "projects");
}

export function historyFile(): string {
  return join(claudeHome(), "history.jsonl");
}

export function cwdToEncoded(cwd: string): string {
  if (cwd.length === 0 || !cwd.startsWith("/")) {
    throw new Error(`cwdToEncoded: expected absolute path, got ${JSON.stringify(cwd)}`);
  }
  return cwd.replace(/[/.]/g, "-");
}
