# cc-dashboard → macOS menu bar app — Design Spec

**Date**: 2026-04-28
**Status**: design approved, plan pending
**Owner**: claudev-cheval

## 1. Goal

Convert `cc-dashboard` from a local web dashboard (Python HTTP server + browser UI) into a self-contained macOS menu bar `.app` that:

- Preserves every cc-dashboard feature (ranked inbox, Restore view, Ghostty focus, resume/fork, open-in-IDE, staleness decay).
- Matches the form-factor and polish of `cctop` (popover, tabs, navigate mode, themes, smart status icon, draggable panel).
- Adds two corpus-mining capabilities surfaced via `/laser` convergence (Decision Log per Repo, Session Compost Heap projection registry).
- Adds an info-rich Session Detail panel surfacing branch timeline, files changed, token usage, load history, and quick actions.
- Supports a one-click Quiet mode for focused coding drills.

**Success criteria**: a single signed `cc-dashboard.app` bundle, no external runtime dependencies, that the user can run from the menu bar in place of the existing browser-based dashboard. Manual `git pull && build` to update.

## 2. Stack & build

| Layer | Choice | Why |
|---|---|---|
| Menu bar UI | Swift / SwiftUI + AppKit | Native feel parity with cctop |
| Backend logic | TypeScript on Bun runtime | Replaces `server.py`; same ergonomic shape, better long-term tooling |
| TS bundling | `bun build --compile` → single binary | Self-contained, signable, no system Node dependency |
| TS deps | None (`Bun.serve` + stdlib only) | Matches existing zero-deps ethos |
| Swift deps | Vendored `KeyboardShortcuts` library (~3 source files copied in) | Global hotkey + recorder UI, no SPM resolution |
| Project gen | `xcodegen` (declarative YAML → `.xcodeproj`) | Diff-friendly project config, gitignore the generated project file |
| Test runners | `bun test` (TS) + `XCTest` (Swift) | Both are built-in, zero deps |
| Auto-update | None | Personal tool; manual rebuild |

## 3. Architecture

Two processes, one bundle:

```
cc-dashboard.app/
  Contents/
    MacOS/cc-dashboard           Swift menu bar executable
    Resources/
      backend/cc-dashboard-backend   TS sidecar, single Bun-compiled binary
      Assets.xcassets                status icons, theme palettes
    Info.plist                       LSUIElement=YES, no Dock icon
```

**IPC**: HTTP on `127.0.0.1:<ephemeral port>`. Swift picks an unused port at launch, passes via `--port <N>` to the sidecar.

**Bundle identity**: `dev.vcheval.cc-dashboard` (placeholder — final string set in `Info.plist` during implementation). Code signed locally with the user's Apple Developer ID for personal use; no notarization required since the app is not distributed.

**Lifecycle**: Swift spawns sidecar at app launch, waits for `/api/health` 200, polls `/api/live` and `/api/recent` on a 2 s timer. Lazy-polls `/api/recent` only when Restore tab is active. SIGTERM on app quit; auto-respawn up to 2× on unexpected sidecar exit, then degrade with a red status icon.

**Persistence**: in-memory indices (INT-C). Cold-start scan rebuilds them in 1–3 s; no disk cache, no schema migrations. fs.watch is reactive on a small surface (the sessions dir + per-live-session transcript files), no recursive watching.

## 4. Components

### 4.1 Swift app

- `App/` — `@main`, AppDelegate, `BackendController` (spawn/monitor sidecar), `APIClient`, `PollingStore`
- `UI/` — `StatusIconView` (with `FlashController`), `PopoverController`, `TabBar`, `LiveListView`, `RestoreListView`, `PanelView`, `SessionDetailView`, `NavigateOverlay`, `KeyboardMonitor`
- `Theme/` — Claude / Tokyo Night / Gruvbox / Nord × dark/light
- `Settings/` — `SettingsStore` (`@AppStorage`), `SettingsView`
- `Vendored/KeyboardShortcuts/` — vendored library files

### 4.2 TS sidecar

- `claude/` — sessions, recent, transcript, classify, history (port of `server.py`)
- `ghostty/` — focus orchestrator, tokenize, applescript wrappers, score
- `actions/` — resume, fork, open-IDE
- `corpus/` — tail watcher, in-memory indices, decisions, projections registry
- `util/` — git, pid (with cctop's PID + start-time tuple liveness check)

### 4.3 API contract

Endpoints retained from current `server.py`: `/api/live`, `/api/recent`, `/api/panel`, `/api/focus`, `/api/resume`, `/api/fork`, `/api/open-ide`, `/api/health`.

New endpoints: `/api/decisions?cwd=`, `/api/session-detail?sid=`, `/api/projections/<name>?cwd=`, `/api/settings`, `/api/shutdown`.

## 5. Features

### 5.1 Preserved from cc-dashboard
Live ranked inbox · Restore 14-day view · "where I left off" panel · Ghostty AX content-match focus · Resume / Fork clipboard · Open in IDE auto-detect · Staleness decay · Keyboard shortcuts (`↑↓/jk/⏎/space/Tab/r`) ported into SwiftUI.

### 5.2 Adopted from cctop
Tabs (Live / Restore / Settings) · Navigate mode (global hotkey, 1–9 badges) · Draggable detachable popover · 4 themes × dark/light · Smart status icon · Native UNNotifications.

### 5.3 Lifted from cctop architecture
1. **PID + start-time tuple liveness check** — replaces naive `kill(pid, 0)`; rejects PID reuse, Ctrl+Z'd processes, orphaned processes.
2. **Pure `FocusStrategy` enum** — separates focus-decision (testable pure logic) from execution (AppKit side-effects).
3. **`NSWorkspace.open(url, withApplicationAt:)`** — replaces `open -a` shell-out; resilient to minimal-PATH relaunch contexts.

### 5.4 Added from /laser convergence

**Decision Log per Repo** — extractor mines user's short replies after assistant questions, deduped per repo; surfaced in the Session Detail panel with a one-click prepend-to-clipboard action.

**Session Compost Heap** — projection registry under `corpus/projections.ts`. Decision Log is the first concrete projection; future projections (gotchas-per-repo, prompts-that-worked, files-that-broke) plug in without re-architecting.

### 5.5 Info-rich Session Detail panel

Push-navigation from a Live row (back arrow returns). Sections:

- Repo / branch header
- Branch timeline this session (HEAD sampled per transcript-write, dedup consecutive)
- Files changed this session (from tool_use Edit/Write/MultiEdit/NotebookEdit events)
- Token usage: input / cache-read / cache-create / output, summed from each assistant turn's `usage` block; with a 200k-context utilization bar
- Load sparkline (tool_use count per minute over session lifetime)
- Last assistant message + open tool
- Decisions panel
- Action row: Focus Terminal · Resume · Fork · Open in IDE

### 5.6 Flashing status icon + Quiet mode

**Flash trigger**: a session transitions into `{PERMISSION_PENDING, TOOL_FAILED, ASK}` from a non-attention state. 1 Hz two-image swap on `NSStatusItem.button.image`. Stops on: popover open, all attention cleared, 30 s auto-cap (configurable), or Quiet mode.

**Quiet mode** (one-click): popover header pill toggle · right-click status icon → preset durations (30 m / 1 h / 4 h / until tomorrow 9 AM / until I unmute) · global hotkey (default `⌃⌥M`, rebindable). While quiet: no flash, no UNNotifications, no sound; status icon shows a moon overlay; data still updates. Persists across relaunches via `@AppStorage`.

### 5.7 Settings tab
Theme · navigate-mode hotkey (rebindable) · quiet-mode hotkey (rebindable) · poll interval · IDE override · flash on attention (toggle) · flash duration cap · notification sound · custom mute durations.

## 6. Data flow (high level)

1. Launch → Swift spawns sidecar → wait for `/api/health` → start poll timer.
2. Sidecar cold-starts: scans `~/.claude/`, builds in-memory indices, opens fs.watch on shallow surface (sessions dir + per-live-session transcript files).
3. Steady state: tail watcher updates indices reactively on transcript appends. `/api/live` reads from memory, not from disk re-tail.
4. User clicks a Live row → push to Session Detail → Swift `GET /api/session-detail?sid=` → render.
5. User actions (focus / resume / fork / open-IDE) flow Swift → POST sidecar → OS (osascript / pbcopy / NSWorkspace).
6. Quit → Swift POSTs `/api/shutdown` → SIGTERM after 500 ms grace.

## 7. Error handling (high level)

- **Sidecar crash**: red status icon, auto-respawn 2×, give up with banner.
- **Permission denials** (Accessibility, Notifications, file system): inline banners with deeplinks to System Settings.
- **fs.watch missed event**: known unmitigated risk — pathological case is a stale classifier until the next transcript write. No safety-net rescan in v1; cheap retrofit if it bites in practice.
- **Ghostty match failures**: existing fallback strategy retained (sticky "find this window" card with branch + last assistant message).
- **Corpus index growth**: bounded eviction (per-session decision/file indices dropped when session ends and 1 h have passed).

## 8. Testing strategy (high level)

- **TS unit tests** (`bun test`) for classifier, staleness decay, tokenize/score, liveness, decision extractor, token summation.
- **TS integration tests** with a fixture `~/.claude/` tree: cold-start, tail-watch, every API endpoint.
- **Swift unit tests** (XCTest) for `resolveFocusStrategy`, theme palette resolution, polling-store sort/badge logic, navigate-mode keyboard handling, flash-controller transition logic.
- **No coverage threshold**; minimum: every endpoint has an integration test, every classifier branch has a unit test, every `FocusStrategy` case has a unit test.

## 9. Migration plan

The current `server.py` + `index.html` stay in the repo during migration (R3). Once the TS sidecar is proven equivalent on real `~/.claude/` data, both are deleted in a follow-up commit. No "web mode" maintained long-term.

## 10. Out of scope (v1)

- Sparkle / auto-update.
- Cross-platform (Linux / Windows).
- Auto-mute when [Cursor / VS Code] is frontmost — deferred to v2.
- Bidirectional control (write prompts into running sessions) — cut by `/laser` Filter 1.
- Repo Collision Radar (cross-session file-stomping detector) — design considered too complex for v1; cut.
- Persistent event log (SQLite) — INT-B was rejected in favor of in-memory INT-C.

## 11. Open questions / assumptions to confirm

- **`bun test`** as the TS test runner (zero deps). UNCONFIRMED — assumed default; flag for explicit user sign-off.
- **Auto-mute when frontmost** — deferred to v2. UNCONFIRMED — confirm v1 scope is fine without it.
- **Vendoring source from `KeyboardShortcuts`** — the exact 2–3 files to copy will be identified during implementation. Not a design-level decision.

## 12. References

- Existing implementation: `server.py` (935 LOC), `index.html` (748 LOC).
- cctop reference repo: `/Users/claudevcheval/Hanalei/cctop/` — see `menubar/CctopMenubar/Models/Session.swift`, `Services/SessionManager.swift`, `Services/FocusTerminal.swift`, `Views/PopupView.swift` for the patterns lifted in §5.3.
- `/laser` convergence output (this session): two survivors retained (Decision Log per Repo, Session Compost Heap); a third (Repo Collision Radar) was cut as too complex for v1.
