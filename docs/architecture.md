# Architecture & internals

For users: see the top-level [README](../README.md). This file is for people
hacking on cc-dashboard.

## Keyboard

In-popover (when the popover is visible):

| Key | Action |
|---|---|
| `↑` `↓` / `j` `k` | navigate rows |
| `⏎` / `space` | focus terminal (Live) / activate row |
| `Tab` | cycle Live / Restore / Settings |
| `r` | force refresh |
| `Esc` | exit nav-mode if active, otherwise close the popover |
| `1`–`9` | when nav-mode is on, jump to that row |

Global (rebindable in Settings → Hotkeys via the vendored
`KeyboardShortcuts.Recorder`):

- Toggle Quiet — default `⌃⌥M`
- Navigate-mode — no default; assign in Settings

## How the focus mechanism works (Ghostty)

Ghostty is a single macOS process with no IPC and no tty→window mapping
exposed via AppleScript (unlike iTerm2). Windows on non-current macOS Spaces
are invisible to the Accessibility API. These are hard constraints.

Strategy: **content-based title matching against the session's early prompts**.

1. Activate Ghostty (`tell application "Ghostty" to activate`) — this makes
   every Ghostty window on the current Space visible to System Events.
2. Enumerate visible Ghostty windows + titles via System Events AX API.
3. For each candidate window, tokenize the title (strip unicode glyphs,
   stopwords, URL percent-encoding) and score token overlap against the
   session's first 5 user prompts + last 3 user prompts + cwd basename.
   Weights: `early=3, cwd=2, recent=1` — Ghostty window titles are set from
   the first substantive prompt in the current working block and stay sticky.
4. Require `score >= 5` and `margin >= 3` over the runner-up to declare a
   confident match (prevents false positives from generic words).
5. `AXRaise` the winning window and set `frontmost`.

If no confident match (window on another Space, brand-new session with no
transcript yet, or ambiguous topic), the popover surfaces a transient
"No terminal window matched" toast — visual cue to find the window manually.

The full pipeline lives in `app/Sources/FocusStrategy/GhosttyFocus.swift`. It
runs in the menu-bar app's process (not the bundled sidecar) so the user's
Accessibility grant on `cc-dashboard.app` actually applies to the AppleScript
caller — see commit history for the rationale.

### One-time macOS permission

On first launch, macOS will prompt for **Accessibility** permission for the
`cc-dashboard` app. Grant once, lives forever — except that unsigned dev
builds re-codesign on every `make app-build`, which invalidates the prior
grant. Workaround for development: remove and re-add cc-dashboard in
System Settings → Privacy & Security → Accessibility after each rebuild.

### Known limitations

- **Cross-Space windows**: the AX API does not enumerate Ghostty windows on
  non-current Spaces. Use Mission Control (`⌃↑`) to find them manually.
- **Resumed sessions**: if a session was resumed with `claude --resume` from
  an older transcript about a different topic, the "early prompts" will be
  from the original topic, not the current work. Matching may pick the old
  topic's window. Work around by using `claude --continue` in a fresh window
  or starting a new session.
- **Tabs**: Ghostty tabs are not exposed via AX. One session per window is
  assumed.

## Data sources

| File                                     | Used for                              |
|------------------------------------------|---------------------------------------|
| `~/.claude/sessions/<pid>.json`          | live session index                    |
| `~/.claude/projects/<enc>/<sid>.jsonl`   | transcripts (main thread)             |
| `~/.claude/history.jsonl`                | recent prompts per repo               |
| git at each cwd                          | branch, dirty count, diff stat        |

The "live" criterion is just: a session file exists in `~/.claude/sessions/`
AND its `pid` is still alive on the system (`isPidAlive(pid, pidStartTime)`).
Closing a terminal without exiting `claude` leaves the process running and
keeps it on the dashboard — that's by design.

## Process layout

```
  ┌─────────────────────────────────────────────────────────┐
  │ cc-dashboard.app  (Swift, menu-bar `LSUIElement`)       │
  │                                                         │
  │   StatusItem ──▶ FlashController ──▶ icon flash         │
  │   PopoverController                                     │
  │     ├─ LiveTab / RestoreTab / SessionDetail             │
  │     ├─ KeyboardMonitor (in-popover ↑↓/j-k/⏎/1-9)        │
  │     ├─ KeyboardShortcuts (vendored, global hotkeys)     │
  │     ├─ ErrorBanner (transient toast)                    │
  │     └─ GhosttyFocus (NSAppleScript, in-process AX)      │
  │                                                         │
  │   spawns ─▶ Contents/Resources/backend/                 │
  │             cc-dashboard-backend  (Bun standalone)      │
  │   parent-death pipe ──▶ child stdin EOF on quit         │
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
  │   POST /api/resume → pbcopy resume command              │
  │   POST /api/fork   → pbcopy fork summary                │
  │   POST /api/open-ide → NSWorkspace bundle-id            │
  └─────────────────────────────────────────────────────────┘
```

No external runtime dependencies. The sidecar binary contains the full Bun
runtime (~63 MB) and is unpacked at build time into the `.app` bundle, so the
app is hermetic — no `bun` / `node` / `python` required on the user's
machine.

The sidecar self-terminates when its parent app dies, via two redundant
mechanisms (`backend/src/server.ts`):

1. **Stdin EOF** (primary): the Swift app pipes the child's stdin and never
   writes to it. When the app exits by any cause — Cmd-Q, SIGKILL, OOM,
   crash — the kernel closes its FDs and the child sees EOF. Fires within
   milliseconds. Gated on the `CC_DASHBOARD_PARENT_PIPE=1` env var so test
   runners (which leave stdin as `/dev/null`) don't trip it.
2. **Ppid poll** (fallback): every 2 s, compares `process.ppid` to the
   value at startup. On macOS, an orphaned child reparents to launchd
   (PID 1), so a change is a reliable death signal.

## Tests

```bash
make test-app    # Swift / XCTest, ~1.5 s
cd backend && bun test    # Bun test runner, ~600 ms
```

Both suites run hermetically — no external services, no real `~/.claude`
reads (backend tests use `CLAUDE_HOME` overrides into `backend/test/fixtures/`).
