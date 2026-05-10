# cc-dashboard

Menu-bar app for managing many Claude Code terminal windows.

Two views on the same data pipeline:

- **Live** — ranked inbox of live sessions. Shows which session needs you next
  (permission pending → tool failed → asking you → idle → working). Press `⏎`
  on a row to focus the owning Ghostty window.
- **Restore** — crash recovery. Shows the most recent session per repo in the
  last 14 days, with a "where I left off" panel: last prompts, Claude's last
  message, open tool calls, git state. Click to copy a `claude --resume`
  command (or a fork summary) to your clipboard.

A **Session Detail** push view (open via the chevron / row tap on Live) shows
files changed, branch history, token usage with a sparkline, and the most
recent assistant turn. The status bar icon flashes when a session needs your
attention; a Quiet-mode toggle suppresses both the flash and the OS-level
notification when you don't want to be interrupted.

## Run

```
make app-build         # builds the .app bundle
make app-run           # opens it
```

The app appears in your menu bar. The Bun-compiled TypeScript sidecar is
bundled inside the `.app` (`Contents/Resources/backend/`) — no Python or Node
required at runtime.

## Build prerequisites

- macOS 14+
- Xcode 15+ Command Line Tools (`xcode-select --install`)
- `xcodegen` (`brew install xcodegen`)
- `bun` (`brew install oven-sh/bun/bun`)

## Keyboard

In-popover (when the popover is visible):

- `↑` `↓` / `j` `k` — navigate rows
- `⏎` / `space` — focus terminal (Live) / activate row
- `Tab` — cycle Live / Restore / Settings
- `r` — force refresh
- `Esc` — exit nav-mode if active, otherwise close the popover
- `1`–`9` — when nav-mode is on, jump to that row

Global (rebindable in Settings → Hotkeys via the vendored
`KeyboardShortcuts.Recorder`):

- Toggle Quiet — default `⌃⌥M`
- Navigate-mode — no default; assign in Settings

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
transcript yet, or ambiguous topic), the popover surfaces a transient
"No terminal window matched" toast — visual cue to find the window manually.

### One-time macOS permission

On first launch, macOS will prompt for **Accessibility** permission for the
`cc-dashboard` app (the running process invokes `osascript` indirectly via
the bundled sidecar). Grant once, lives forever.

### Known limitations

- **Cross-space windows**: the AX API does not enumerate Ghostty windows on
  non-current spaces. Use Mission Control (`⌃↑`) to find them manually.
- **Resumed sessions**: if a session was resumed with `claude --resume` from
  an older transcript about a different topic, the "early prompts" will be
  from the original topic, not the current work. Matching may pick the old
  topic's window. Work around by using `claude --continue` in a fresh window
  or starting a new session.
- **Tabs**: Ghostty tabs are not exposed via AX. One session per window is
  assumed (confirmed by the developer's setup).

## Data sources

| File                                     | Used for                              |
|------------------------------------------|---------------------------------------|
| `~/.claude/sessions/<pid>.json`          | live session index                    |
| `~/.claude/projects/<enc>/<sid>.jsonl`   | transcripts (main thread)             |
| `~/.claude/history.jsonl`                | recent prompts per repo               |
| git at each cwd                          | branch, dirty count, diff stat        |

## Architecture

```
  ┌─────────────────────────────────────────────────────────┐
  │ cc-dashboard.app  (Swift, menu-bar `LSUIElement`)       │
  │                                                         │
  │   StatusItem ──▶ FlashController ──▶ icon flash         │
  │   PopoverController                                     │
  │     ├─ LiveTab / RestoreTab / SessionDetail             │
  │     ├─ KeyboardMonitor (in-popover ↑↓/j-k/⏎/1-9)        │
  │     ├─ KeyboardShortcuts (vendored, global hotkeys)     │
  │     └─ ErrorBanner (transient toast)                    │
  │                                                         │
  │   spawns ─▶ Contents/Resources/backend/                 │
  │             cc-dashboard-backend  (Bun standalone)      │
  └─────────────────────────────────────────────────────────┘
                            │  HTTP on 127.0.0.1:<ephemeral>
                            ▼
  ┌─────────────────────────────────────────────────────────┐
  │ TypeScript sidecar (Bun, bundled at build time)         │
  │                                                         │
  │   ~/.claude/sessions/*.json ──┐                         │
  │   ~/.claude/projects/.../...jsonl ─┼─▶ classifier       │
  │   ~/.claude/history.jsonl ────┘   (5-state event)       │
  │                                                         │
  │   GET /api/health                                       │
  │   GET /api/live          → ranked inbox                 │
  │   GET /api/recent        → recent-by-repo               │
  │   GET /api/panel?cwd     → Decision Log + git diff      │
  │   GET /api/decisions?cwd → projection registry          │
  │   GET /api/session-detail?sid                           │
  │   POST /api/focus  → osascript → Ghostty AXRaise        │
  │   POST /api/resume → pbcopy resume command              │
  │   POST /api/fork   → pbcopy fork summary                │
  │   POST /api/open-ide → NSWorkspace bundle-id            │
  └─────────────────────────────────────────────────────────┘
```

No external runtime dependencies. The sidecar binary contains the full Bun
runtime (~63 MB) and is unpacked at build time into the `.app` bundle, so
the app is hermetic — no `bun` / `node` / `python` required on the user's
machine. The sidecar self-terminates when its parent app dies (`getppid()`
poll), so force-quitting the app doesn't leak background processes.
