// API response types — must remain stable, Swift Codable mirrors these.

export type Event =
  | "PERMISSION_PENDING"
  | "TOOL_FAILED"
  | "ASK"
  | "WORKING"
  | "IDLE_AFTER_COMPLETE"
  | "CLEAR";

export interface OpenTool {
  name: string;
  id?: string;
}

export interface ClassifyResult {
  event: Event;
  reason: string;
  priority: number;
  last_user: string;
  last_assistant: string;
  open_tool: OpenTool | null;
}

export interface GitInfo {
  branch: string | null;
  dirty: number;
  last_commit: string | null;
}

export interface LiveSession extends ClassifyResult {
  pid: number;
  sessionId: string;
  cwd: string;
  repo: string;
  branch: string | null;
  dirty: number;
  started_at: number;
  last_activity: number;       // ms epoch
  age_sec: number;
  stale_decay: number;
  transcript_found: boolean;
}

export interface RecentRepo extends ClassifyResult {
  cwd: string;
  repo: string;
  branch: string | null;
  dirty: number;
  last_commit: string | null;
  sessionId: string;
  last_activity: number;
}

export interface Panel {
  cwd: string;
  repo: string;
  sessionId: string | null;
  transcript_found: boolean;
  git: GitInfo;
  diff_summary: string | null;
  recent_prompts: { display: string; timestamp?: string }[];
  last_user: string;
  last_assistant: string;
  event: Event;
  reason: string;
  open_tool: OpenTool | null;
}

export interface SessionDetail {
  sessionId: string;
  cwd: string;
  repo: string;
  branch: string | null;
  branch_history: string[];
  files_changed: { path: string; edits: number; last_touch: number }[];
  tokens: { input: number; cached_read: number; cached_create: number; output: number; context_limit: number };
  load_history: number[];   // tool_use count per minute, length 32
  last_assistant: string;
  open_tool: OpenTool | null;
  decisions: { q: string; a: string }[];
  source: "cc" | "opencode" | "pi" | "codex";
  age_sec: number;
}

export interface FocusResult {
  ok: boolean;
  matched: boolean;
  reason?: string;
  detail?: string;
  window_index?: number;
  matched_title?: string;
  score?: number;
  margin?: number;
}

export interface ResumeResult {
  command: string;
  copied_to_clipboard: boolean;
}

export interface ForkResult {
  summary: string;
  copied_to_clipboard: boolean;
}

export interface OpenIdeResult {
  ok: boolean;
  ide?: string;
  error?: string;
  detail?: string;
}
