# cc-dashboard

Local web dashboard for managing many Claude Code terminal windows.

Two views on the same data pipeline:

- **Live** — ranked inbox of live sessions. Shows which session needs you next
  (permission pending → tool failed → asking you → idle → working). Click to
  focus the owning Ghostty window.
- **Restore** — crash recovery. Shows the most recent session per repo in the
  last 14 days, with a "where I left off" panel: last prompts, Claude's last
  message, open tool calls, git state. Click to copy a `claude --resume`
  command (or a fork summary) to your clipboard.

## Run

```
python3 server.py
```

Opens at http://localhost:7777. Auto-refreshes every 3 seconds.

## Keyboard

- `↑` `↓` / `j` `k` — navigate rows
- `⏎` — focus terminal (Live) / copy resume command (Restore)
- `space` — focus top row
- `Tab` — toggle Live / Restore
- `r` — force refresh

## How the focus mechanism works (Ghostty)

Ghostty is a single macOS process with no IPC and no tty→window mapping
exposed via AppleScript (unlike iTerm2). Windows on non-current macOS spaces
are invisible to the Accessibility API. These are hard constraints.

Strategy: **content-based title matching against the session's early prompts**.

1. Activate Ghostty (`tell application "Ghostty" to activate`) — this makes
   every Ghostty window on the current space visible to System Events.
2. Enumerate visible Ghostty windows + titles via System Events AX API.
3. For each candidate window, tokenize the title (strip unicode glyphs,
   stopwords, URL percent-encoding) and score token overlap against the
   session's first 5 user prompts + last 3 user prompts + cwd basename.
   Weights: `early=3, cwd=2, recent=1` — Ghostty window titles are set from
   the first substantive prompt in the current working block and stay sticky.
4. Require `score >= 5` and `margin >= 3` over the runner-up to declare a
   confident match (prevents false positives from generic words).
5. `AXRaise` the winning window and set `frontmost`.

If no confident match (window on another space, brand-new session with no
transcript yet, or ambiguous topic), fall back to the "find this window"
sticky card — a small corner overlay with repo, branch, Claude's last
message, and your last prompt, so you can visually pick the right window.

### One-time macOS permission

On first use, macOS will prompt for **Accessibility** permission for whichever
process is running `osascript` (typically your terminal emulator or iTerm2
if that's where you launched `python3 server.py`). Grant once, lives forever.

### Current accuracy on this machine

With 5 Ghostty windows visible across 2 macOS spaces and 8 live sessions,
the matcher correctly identifies all 4 sessions whose windows are on the
active space, scoring each between 6–12 with clear margins. The 4 sessions
whose windows are on other spaces correctly report "no match" and get the
sticky fallback.

### Known limitations

- **Cross-space windows**: the AX API does not enumerate Ghostty windows on
  non-current spaces. Use Mission Control (`⌃↑`) to find them manually.
- **Resumed sessions**: if a session was resumed with `claude --resume` from
  an older transcript about a different topic, the "early prompts" will be
  from the original topic, not the current work. Matching may pick the old
  topic's window. Work around by using `claude --continue` in a fresh window
  or starting a new session.
- **Tabs**: Ghostty tabs are not exposed via AX. One session per window is
  assumed (confirmed by user's setup).

## Data sources

| File                                     | Used for                              |
|------------------------------------------|---------------------------------------|
| `~/.claude/sessions/<pid>.json`          | live session index                    |
| `~/.claude/projects/<enc>/<sid>.jsonl`   | transcripts (main thread)             |
| `~/.claude/history.jsonl`                | recent prompts per repo               |
| git at each cwd                          | branch, dirty count, diff stat        |

## Architecture

```
  ~/.claude/sessions/*.json          fs.watch (not yet; polls)
        │
        ▼
  load_live_sessions() ──┐
                         │     classify()
  ~/.claude/projects ────┼──→  event: ASK|PERMISSION_PENDING|TOOL_FAILED|
     /*/<sid>.jsonl      │           WORKING|IDLE_AFTER_COMPLETE|CLEAR
                         │
  ~/.claude/history.jsonl ┘
        │
        ▼
  HTTP server (:7777) ──→  single-page frontend (polls every 3s)
        │
        ├── POST /api/focus   → osascript → Ghostty AXRaise
        ├── POST /api/resume  → pbcopy `cd && claude --resume <sid>`
        └── POST /api/fork    → pbcopy markdown summary for fresh session
```

No external dependencies. Python stdlib + osascript + pbcopy + git.
