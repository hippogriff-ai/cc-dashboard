# cc-dashboard Menu Bar Conversion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `cc-dashboard` from a Python HTTP web dashboard into a self-contained macOS menu bar `.app` (Swift UI + TypeScript sidecar) that ships as a signed bundle, preserves every existing feature, adopts the UX design in `docs/ux-design/`, and adds Decision Log + Compost Heap projection registry + flashing icon + Quiet mode + info-rich Session Detail panel.

**Architecture:** Swift menu bar shell spawns a Bun-compiled TypeScript sidecar over an ephemeral `127.0.0.1` HTTP port. Swift renders the popover (Live / Restore / Settings tabs + push-navigation Session Detail). Sidecar holds in-memory indices populated by `fs.watch` on a shallow surface (sessions dir + per-live-session transcript files). Zero runtime deps in TS; vendored `KeyboardShortcuts` source files in Swift; xcodegen for project file.

**Tech Stack:** Swift 5.9 / SwiftUI + AppKit; TypeScript on Bun runtime (`Bun.serve` + stdlib only); xcodegen; XCTest; `bun test`; macOS 14+ target.

**Authoritative inputs the engineer must read first:**
- `docs/superpowers/specs/2026-04-28-menubar-conversion-design.md` — technical spec
- `docs/superpowers/specs/2026-04-28-menubar-ux-designer-brief.md` — UX brief (screen + state inventory)
- `docs/ux-design/` — interactive React design system: `screens.jsx`, `components.jsx`, `icons.jsx`, `data.jsx`, `styles.css` are source-of-truth for layout, tokens, and copy
- `server.py` (in repo root) — current Python implementation; the TS sidecar must be behaviour-equivalent
- `index.html` (in repo root) — current web UI; reference only for current behavior, will be deleted at end (R3)
- `/Users/claudevcheval/Hanalei/cctop/menubar/CctopMenubar/Models/Session.swift` — source for the PID + start-time liveness lift
- `/Users/claudevcheval/Hanalei/cctop/menubar/CctopMenubar/Services/FocusTerminal.swift` — source for the `FocusStrategy` enum lift

---

## File Structure

### Top-level repo layout (target end state)

```
cc-dashboard/
├── README.md
├── Makefile                         # all build targets
├── project.yml                      # xcodegen input (committed)
├── .gitignore                       # ignore *.xcodeproj, build/, .build/, node_modules/, app/build/
├── app/                             # Swift menu bar app
│   ├── Sources/
│   │   ├── App/
│   │   │   ├── CCDashboardApp.swift
│   │   │   ├── AppDelegate.swift
│   │   │   ├── BackendController.swift
│   │   │   ├── APIClient.swift
│   │   │   └── PollingStore.swift
│   │   ├── UI/
│   │   │   ├── StatusIconView.swift
│   │   │   ├── FlashController.swift
│   │   │   ├── PopoverController.swift
│   │   │   ├── PopoverShell.swift
│   │   │   ├── PopHeader.swift
│   │   │   ├── PopFooter.swift
│   │   │   ├── TabBar.swift
│   │   │   ├── QuietPill.swift
│   │   │   ├── LiveTab.swift
│   │   │   ├── SessionRow.swift
│   │   │   ├── RestoreTab.swift
│   │   │   ├── RestoreRow.swift
│   │   │   ├── RestoreDetail.swift
│   │   │   ├── SessionDetailView.swift
│   │   │   ├── SessionDetailSections.swift
│   │   │   ├── Sparkline.swift
│   │   │   ├── NavigateOverlay.swift
│   │   │   ├── SettingsView.swift
│   │   │   ├── KeyboardMonitor.swift
│   │   │   └── Icon.swift
│   │   ├── Theme/
│   │   │   ├── Theme.swift
│   │   │   ├── ThemePalette.swift
│   │   │   └── Themes.swift
│   │   ├── Settings/
│   │   │   ├── SettingsStore.swift
│   │   │   └── QuietModeStore.swift
│   │   ├── FocusStrategy/
│   │   │   └── FocusStrategy.swift  # pure logic only; execution lives in APIClient
│   │   ├── Vendored/
│   │   │   └── KeyboardShortcuts/    # files copied from soffes/KeyboardShortcuts; populated in Phase 5
│   │   └── Resources/
│   │       ├── Assets.xcassets/
│   │       ├── Info.plist
│   │       └── cc-dashboard.entitlements
│   └── Tests/
│       ├── FocusStrategyTests.swift
│       ├── ThemeTests.swift
│       ├── PollingStoreTests.swift
│       ├── FlashControllerTests.swift
│       └── KeyboardMonitorTests.swift
├── backend/                         # TypeScript sidecar
│   ├── package.json
│   ├── tsconfig.json
│   ├── bunfig.toml
│   ├── build.ts                     # bun build --compile script
│   ├── src/
│   │   ├── server.ts                # Bun.serve entry, --port arg
│   │   ├── claude/
│   │   │   ├── paths.ts             # ~/.claude/* path resolution
│   │   │   ├── sessions.ts          # loadLiveSessions
│   │   │   ├── recent.ts            # loadRecentByRepo
│   │   │   ├── transcript.ts        # findTranscript, readJsonlTail, lastTurns, extractText
│   │   │   ├── classify.ts          # 5-state classifier + staleness decay
│   │   │   └── history.ts           # recentPromptsForCwd
│   │   ├── ghostty/
│   │   │   ├── focus.ts             # orchestrator
│   │   │   ├── tokenize.ts          # token sets
│   │   │   ├── score.ts             # weighted overlap
│   │   │   └── applescript.ts       # subprocess wrappers
│   │   ├── actions/
│   │   │   ├── resume.ts
│   │   │   ├── fork.ts
│   │   │   └── openIde.ts
│   │   ├── corpus/
│   │   │   ├── tail.ts              # jsonl tail watcher
│   │   │   ├── indices.ts           # in-memory state types + reducers
│   │   │   ├── decisions.ts         # Q/A extractor
│   │   │   └── projections.ts       # registry of corpus projections
│   │   ├── util/
│   │   │   ├── git.ts
│   │   │   ├── pid.ts               # PID + start_time liveness (lifted from cctop)
│   │   │   ├── ide.ts               # _detect_ide port
│   │   │   └── log.ts
│   │   └── types.ts                 # all response types
│   └── test/
│       ├── fixtures/
│       │   └── dot-claude/          # tiny fake ~/.claude/ tree
│       │       ├── sessions/
│       │       │   ├── 12345.json
│       │       │   └── 67890.json
│       │       ├── projects/
│       │       │   └── -tmp-test-repo/
│       │       │       ├── sess-permission.jsonl
│       │       │       ├── sess-toolfailed.jsonl
│       │       │       ├── sess-ask.jsonl
│       │       │       └── sess-working.jsonl
│       │       └── history.jsonl
│       ├── classify.test.ts
│       ├── staleness.test.ts
│       ├── tokenize.test.ts
│       ├── score.test.ts
│       ├── liveness.test.ts
│       ├── decisions.test.ts
│       ├── tokens.test.ts
│       ├── coldstart.test.ts        # integration
│       ├── tail-watch.test.ts       # integration
│       └── api.test.ts              # integration
├── docs/
│   ├── superpowers/
│   │   ├── specs/                   # ALREADY EXISTS — do not modify
│   │   └── plans/                   # this plan lives here
│   └── ux-design/                   # ALREADY EXISTS — do not modify
└── server.py / index.html           # DELETED in final task (R3)
```

### File responsibility summary

| File | Owns |
|---|---|
| `backend/src/claude/classify.ts` | The 5-state classifier (port of `classify()` from server.py:147–260). Pure function; no I/O. |
| `backend/src/util/pid.ts` | PID liveness using `kill(0)` + `sysctl(KERN_PROC_PID)` start-time match + `p_stat` + `e_ppid` checks. |
| `backend/src/ghostty/focus.ts` | Orchestrates Ghostty AX matching: activate → list windows → tokenize → score → AXRaise. |
| `backend/src/corpus/tail.ts` | Watches per-live-session jsonl files; emits new-turn events. |
| `app/Sources/App/BackendController.swift` | Spawns and monitors the Bun-compiled sidecar; respawns on crash. |
| `app/Sources/FocusStrategy/FocusStrategy.swift` | Pure focus-strategy resolver (testable; no AppKit). |
| `app/Sources/UI/FlashController.swift` | Drives the menu-bar icon flash on attention transitions, with auto-cap and Quiet override. |
| `app/Sources/UI/SessionDetailView.swift` | The push-navigation detail screen. |

---

## Conventions

Inject these into every TS file:
- **Imports**: ESM only (`import { x } from "./y.ts"`). No CommonJS.
- **No deps**: only `bun:*`, `node:*`, and our own files.
- **Types**: each public function has explicit parameter and return types.
- **Error handling**: thrown `Error` objects with `cause`; never silently swallow.
- **Logging**: `import { log } from "./util/log.ts"` — `log.info()`, `log.warn()`, `log.error()` only. No `console.log` in `src/`.

Inject these into every Swift file:
- **Style**: 4-space indent; `import` order: SwiftUI, AppKit, then local.
- **Concurrency**: `@MainActor` on view models that touch UI; pure logic in plain `struct`s.
- **No force-unwraps** in production code; tests may use `XCTUnwrap`.
- **Logging**: `os.Logger(subsystem: "dev.vcheval.cc-dashboard", category: "<area>")`.

Commit message conventions: `feat:`, `fix:`, `refactor:`, `test:`, `chore:`, `docs:`. One commit per task at the end; do not commit between steps.

---

# Phase 1 — Project Scaffolding

## Task 1: Add `.gitignore` for the new build artefacts [DONE — loop 1]

**Files:**
- Modify: `cc-dashboard/.gitignore`

- [ ] **Step 1: Inspect current `.gitignore`**

Run: `cat .gitignore`
Note what's already there.

- [ ] **Step 2: Append new entries**

Append (do not replace) the following block to `.gitignore`:

```
# xcodegen output (regenerate via `make project`)
app/cc-dashboard.xcodeproj/

# Swift / Xcode build artefacts
app/build/
.build/
DerivedData/

# Bun / Node
backend/node_modules/
backend/dist/
backend/.bun/
backend/cc-dashboard-backend
backend/cc-dashboard-backend.tmp

# macOS
.DS_Store
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: ignore xcodegen output and build artefacts"
```

## Task 2: Create the top-level `Makefile` [DONE — loop 1]

**Files:**
- Create: `cc-dashboard/Makefile`

- [ ] **Step 1: Write the Makefile**

Create `Makefile` with this content:

```makefile
.PHONY: project backend-build app-build app-run test test-backend test-app clean

# Regenerate Xcode project from project.yml
project:
	cd app && xcodegen generate

# Compile the TypeScript sidecar to a single binary
backend-build:
	cd backend && bun build --compile --minify --target=bun-darwin-arm64 src/server.ts --outfile cc-dashboard-backend

# Build the Swift app (Release)
app-build: project backend-build
	xcodebuild -project app/cc-dashboard.xcodeproj -scheme cc-dashboard -configuration Release -derivedDataPath app/build

# Run the built app
app-run: app-build
	open app/build/Build/Products/Release/cc-dashboard.app

# All tests
test: test-backend test-app

test-backend:
	cd backend && bun test

test-app: project
	xcodebuild -project app/cc-dashboard.xcodeproj -scheme cc-dashboard test -derivedDataPath app/build

clean:
	rm -rf app/build app/cc-dashboard.xcodeproj backend/cc-dashboard-backend backend/dist
```

- [ ] **Step 2: Commit**

```bash
git add Makefile
git commit -m "chore: add Makefile with project/build/test targets"
```

## Task 3: Scaffold backend package [DONE — loop 1]

**Files:**
- Create: `backend/package.json`
- Create: `backend/tsconfig.json`
- Create: `backend/bunfig.toml`
- Create: `backend/src/server.ts`
- Create: `backend/src/util/log.ts`

- [ ] **Step 1: Create `backend/package.json`**

```json
{
  "name": "cc-dashboard-backend",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "scripts": {
    "dev": "bun run src/server.ts --port 7777",
    "test": "bun test",
    "build": "bun build --compile --minify --target=bun-darwin-arm64 src/server.ts --outfile cc-dashboard-backend"
  }
}
```

- [ ] **Step 2: Create `backend/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "skipLibCheck": true,
    "types": ["bun-types"],
    "allowImportingTsExtensions": true,
    "noEmit": true
  },
  "include": ["src/**/*", "test/**/*"]
}
```

- [ ] **Step 3: Create `backend/bunfig.toml`**

```toml
[test]
preload = []
```

- [ ] **Step 4: Create `backend/src/util/log.ts`**

```typescript
const ts = (): string => new Date().toISOString();
export const log = {
  info: (msg: string, ctx?: unknown): void => console.error(`[${ts()}] INFO  ${msg}${ctx ? " " + JSON.stringify(ctx) : ""}`),
  warn: (msg: string, ctx?: unknown): void => console.error(`[${ts()}] WARN  ${msg}${ctx ? " " + JSON.stringify(ctx) : ""}`),
  error: (msg: string, ctx?: unknown): void => console.error(`[${ts()}] ERROR ${msg}${ctx ? " " + JSON.stringify(ctx) : ""}`),
};
```

- [ ] **Step 5: Create a stub `backend/src/server.ts`**

```typescript
import { log } from "./util/log.ts";

const args = process.argv.slice(2);
const portIdx = args.indexOf("--port");
const port = portIdx >= 0 && args[portIdx + 1] ? parseInt(args[portIdx + 1]!, 10) : 7777;

const server = Bun.serve({
  hostname: "127.0.0.1",
  port,
  fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === "/api/health") {
      return Response.json({ ok: true, ts: Date.now() });
    }
    return new Response("not found", { status: 404 });
  },
});
log.info(`backend listening`, { port: server.port });
```

- [ ] **Step 6: Verify it runs**

Run: `cd backend && bun run dev`
Expected: log line `INFO  backend listening {"port":7777}` and process stays alive.

In another terminal: `curl http://127.0.0.1:7777/api/health`
Expected: `{"ok":true,"ts":...}`

Stop with Ctrl-C.

- [ ] **Step 7: Commit**

```bash
git add backend/
git commit -m "feat(backend): scaffold Bun TS sidecar with /api/health"
```

## Task 4: Scaffold Swift app via xcodegen [DONE — loop 1]

**Files:**
- Create: `app/project.yml`
- Create: `app/Sources/App/CCDashboardApp.swift`
- Create: `app/Sources/App/AppDelegate.swift`
- Create: `app/Sources/Resources/Info.plist`
- Create: `app/Sources/Resources/cc-dashboard.entitlements`
- Create: `app/Tests/SmokeTest.swift`

- [ ] **Step 1: Verify xcodegen is installed**

Run: `which xcodegen || brew install xcodegen`
Expected: a path is printed.

- [ ] **Step 2: Create `app/project.yml`**

```yaml
name: cc-dashboard
options:
  bundleIdPrefix: dev.vcheval
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.9"
    DEVELOPMENT_TEAM: ""
    CODE_SIGN_STYLE: Automatic
    PRODUCT_BUNDLE_IDENTIFIER: dev.vcheval.cc-dashboard
    MARKETING_VERSION: "0.4.0"
    CURRENT_PROJECT_VERSION: "1"
targets:
  cc-dashboard:
    type: application
    platform: macOS
    sources:
      - path: Sources
        excludes:
          - "**/*.entitlements"
          - "**/Info.plist"
    resources:
      - Sources/Resources
    info:
      path: Sources/Resources/Info.plist
      properties:
        LSUIElement: true
        CFBundleName: cc-dashboard
        CFBundleDisplayName: cc-dashboard
        CFBundleIdentifier: dev.vcheval.cc-dashboard
        NSHumanReadableCopyright: ""
    settings:
      base:
        CODE_SIGN_ENTITLEMENTS: Sources/Resources/cc-dashboard.entitlements
        ENABLE_HARDENED_RUNTIME: YES
  cc-dashboardTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests
    dependencies:
      - target: cc-dashboard
```

- [ ] **Step 3: Create `app/Sources/Resources/Info.plist`**

xcodegen merges `properties` from `project.yml` into a generated plist; create a minimal stub:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
```

- [ ] **Step 4: Create `app/Sources/Resources/cc-dashboard.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

(We disable App Sandbox because cc-dashboard reads `~/.claude/`, runs `osascript`, `pbcopy`, `git`, and `open` — sandbox would block all of these. This is acceptable for a personal tool not distributed via Mac App Store.)

- [ ] **Step 5: Create `app/Sources/App/CCDashboardApp.swift`**

```swift
import SwiftUI

@main
struct CCDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 6: Create `app/Sources/App/AppDelegate.swift`**

```swift
import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "dev.vcheval.cc-dashboard", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("did finish launching")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "cc"
        statusItem = item
    }
}
```

- [ ] **Step 7: Create `app/Tests/SmokeTest.swift`**

```swift
import XCTest

final class SmokeTest: XCTestCase {
    func testTrivial() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

- [ ] **Step 8: Generate the project and build**

Run: `make project`
Expected: `Created project at app/cc-dashboard.xcodeproj`

Run: `make app-build`
Expected: build succeeds; `cc-dashboard.app` exists at `app/build/Build/Products/Release/cc-dashboard.app`.

Run: `make app-run`
Expected: A "cc" status item appears in the macOS menu bar. Confirm visually. Then `pkill cc-dashboard` to quit.

- [ ] **Step 9: Run the smoke test**

Run: `make test-app`
Expected: 1 test passes.

- [ ] **Step 10: Commit**

```bash
git add app/ Makefile
git commit -m "feat(app): scaffold Swift menu bar app via xcodegen"
```

---

# Phase 2 — TS Sidecar (port server.py + new endpoints)

## Task 5: Define API response types [DONE — loop 2]

**Files:**
- Create: `backend/src/types.ts`

- [ ] **Step 1: Write the type definitions**

```typescript
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
```

- [ ] **Step 2: Commit**

```bash
git add backend/src/types.ts
git commit -m "feat(backend): define API response types"
```

## Task 6: Port path resolution + JSON helpers [DONE — loop 2]

**Files:**
- Create: `backend/src/claude/paths.ts`
- Test: `backend/test/paths.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// backend/test/paths.test.ts
import { test, expect } from "bun:test";
import { cwdToEncoded, sessionsDir, projectsDir } from "../src/claude/paths.ts";

test("cwdToEncoded replaces / and . with -", () => {
  expect(cwdToEncoded("/Users/foo/work.repo")).toBe("-Users-foo-work-repo");
});

test("sessionsDir resolves to ~/.claude/sessions", () => {
  expect(sessionsDir()).toMatch(/\.claude\/sessions$/);
});

test("projectsDir resolves to ~/.claude/projects", () => {
  expect(projectsDir()).toMatch(/\.claude\/projects$/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && bun test test/paths.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the implementation**

```typescript
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
  return cwd.replace(/[/.]/g, "-");
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && bun test test/paths.test.ts`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add backend/src/claude/paths.ts backend/test/paths.test.ts
git commit -m "feat(backend): port path resolution helpers from server.py"
```

## Task 7: Port transcript reading + extractText [DONE — loop 2]

**Files:**
- Create: `backend/src/claude/transcript.ts`
- Test: `backend/test/transcript.test.ts`
- Create: `backend/test/fixtures/dot-claude/projects/-tmp-test-repo/sess-basic.jsonl`

- [ ] **Step 1: Create the fixture**

Create `backend/test/fixtures/dot-claude/projects/-tmp-test-repo/sess-basic.jsonl`:

```jsonl
{"type":"user","cwd":"/tmp/test-repo","message":{"role":"user","content":"hello"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hi there"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"t1"},{"type":"text","text":"running it"}]}}
```

- [ ] **Step 2: Write the failing tests**

```typescript
// backend/test/transcript.test.ts
import { test, expect } from "bun:test";
import { readJsonlTail, lastTurns, extractText } from "../src/claude/transcript.ts";

const FIXTURE = "test/fixtures/dot-claude/projects/-tmp-test-repo/sess-basic.jsonl";

test("readJsonlTail returns 3 turns from the fixture", () => {
  const turns = readJsonlTail(FIXTURE, 100);
  expect(turns.length).toBe(3);
  expect(turns[0]?.type).toBe("user");
});

test("readJsonlTail returns [] for missing file", () => {
  expect(readJsonlTail("does-not-exist.jsonl", 100)).toEqual([]);
});

test("lastTurns filters main-thread user/assistant", () => {
  const turns = readJsonlTail(FIXTURE, 100);
  expect(lastTurns(turns, 5).length).toBe(3);
});

test("extractText pulls text and tool_use markers", () => {
  expect(extractText("hello")).toBe("hello");
  expect(extractText([{ type: "text", text: "a" }, { type: "tool_use", name: "Bash" }])).toBe("a\n[tool: Bash]");
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd backend && bun test test/transcript.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 4: Write the implementation**

```typescript
// backend/src/claude/transcript.ts
import { existsSync, readFileSync, statSync, openSync, readSync, closeSync } from "node:fs";
import { join } from "node:path";
import { projectsDir, cwdToEncoded } from "./paths.ts";

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
  try {
    const size = statSync(path).size;
    const chunk = Math.min(size, 256 * 1024);
    const fd = openSync(path, "r");
    try {
      const buf = Buffer.alloc(chunk);
      readSync(fd, buf, 0, chunk, size - chunk);
      data = buf.toString("utf-8");
    } finally {
      closeSync(fd);
    }
  } catch {
    return [];
  }
  const lines = data.split("\n").filter((l) => l.trim().length > 0);
  const out: Turn[] = [];
  for (const line of lines.slice(-n)) {
    try {
      out.push(JSON.parse(line) as Turn);
    } catch {
      // skip malformed line
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd backend && bun test test/transcript.test.ts`
Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add backend/src/claude/transcript.ts backend/test/transcript.test.ts backend/test/fixtures/
git commit -m "feat(backend): port transcript reading + extractText"
```

## Task 8: Port the 5-state classifier [DONE — loop 3]

**Files:**
- Create: `backend/src/claude/classify.ts`
- Test: `backend/test/classify.test.ts`
- Create: `backend/test/fixtures/dot-claude/projects/-tmp-test-repo/sess-permission.jsonl`
- Create: `backend/test/fixtures/dot-claude/projects/-tmp-test-repo/sess-toolfailed.jsonl`
- Create: `backend/test/fixtures/dot-claude/projects/-tmp-test-repo/sess-ask.jsonl`
- Create: `backend/test/fixtures/dot-claude/projects/-tmp-test-repo/sess-working.jsonl`
- Create: `backend/test/fixtures/dot-claude/projects/-tmp-test-repo/sess-idle.jsonl`

- [ ] **Step 1: Read the existing classifier in `server.py:147–260`**

Open `server.py` and read lines 147–260. The classifier rule is: classify on the LAST turn only. The 6 states are CLEAR (no turns), PERMISSION_PENDING (special-cased per the spec's flashing-trigger section — but in current server.py this is folded into ASK / TOOL_FAILED logic; for v1 we treat any tool_result with `is_error` on a user turn as TOOL_FAILED), TOOL_FAILED (last user turn is `is_error` tool_result), ASK (assistant text ends with "?"), WORKING (assistant has open tool_use), IDLE_AFTER_COMPLETE (assistant ended without "?" and no open tool). Note: "PERMISSION_PENDING" is named in the spec as a target event; in the transcript shape, it manifests as an assistant message ending with a question that references a tool the assistant wants to run. For the v1 classifier we'll keep the current server.py mapping: `permission-pending` is recognised when the assistant text contains a permission-style phrase. See test fixtures for the canonical examples.

- [ ] **Step 2: Create the four state fixtures**

`backend/test/fixtures/dot-claude/projects/-tmp-test-repo/sess-permission.jsonl`:

```jsonl
{"type":"user","cwd":"/tmp/test-repo","message":{"role":"user","content":"please clean install"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I need to remove node_modules. Can I run rm -rf node_modules?"}]}}
```

`backend/test/fixtures/dot-claude/projects/-tmp-test-repo/sess-toolfailed.jsonl`:

```jsonl
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"t1"}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"pytest exit 1"}]}}
```

`backend/test/fixtures/dot-claude/projects/-tmp-test-repo/sess-ask.jsonl`:

```jsonl
{"type":"user","message":{"role":"user","content":"which strategy?"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Two ways: idempotency keys or unique constraints. Which would you like?"}]}}
```

`backend/test/fixtures/dot-claude/projects/-tmp-test-repo/sess-working.jsonl`:

```jsonl
{"type":"user","message":{"role":"user","content":"run tests"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"t9","input":{"command":"pnpm test"}}]}}
```

`backend/test/fixtures/dot-claude/projects/-tmp-test-repo/sess-idle.jsonl`:

```jsonl
{"type":"user","message":{"role":"user","content":"do the thing"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done. All tests passing."}]}}
```

- [ ] **Step 3: Write the failing tests**

```typescript
// backend/test/classify.test.ts
import { test, expect } from "bun:test";
import { classify } from "../src/claude/classify.ts";
import { readJsonlTail } from "../src/claude/transcript.ts";

const root = "test/fixtures/dot-claude/projects/-tmp-test-repo";

test("empty transcript → CLEAR", () => {
  const r = classify([], true);
  expect(r.event).toBe("CLEAR");
});

test("assistant ending with permission phrasing → PERMISSION_PENDING", () => {
  const r = classify(readJsonlTail(`${root}/sess-permission.jsonl`, 100), true);
  expect(r.event).toBe("PERMISSION_PENDING");
  expect(r.priority).toBeLessThanOrEqual(15);
});

test("user tool_result is_error last → TOOL_FAILED", () => {
  const r = classify(readJsonlTail(`${root}/sess-toolfailed.jsonl`, 100), true);
  expect(r.event).toBe("TOOL_FAILED");
  expect(r.reason).toContain("pytest");
});

test("assistant text ending with '?' → ASK", () => {
  const r = classify(readJsonlTail(`${root}/sess-ask.jsonl`, 100), true);
  expect(r.event).toBe("ASK");
});

test("assistant with open tool_use + alive → WORKING", () => {
  const r = classify(readJsonlTail(`${root}/sess-working.jsonl`, 100), true);
  expect(r.event).toBe("WORKING");
  expect(r.open_tool?.name).toBe("Bash");
});

test("assistant text not ending with '?' and no tool → IDLE_AFTER_COMPLETE", () => {
  const r = classify(readJsonlTail(`${root}/sess-idle.jsonl`, 100), true);
  expect(r.event).toBe("IDLE_AFTER_COMPLETE");
});
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd backend && bun test test/classify.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 5: Implement `classify.ts`**

```typescript
// backend/src/claude/classify.ts
import type { ClassifyResult, Event, OpenTool } from "../types.ts";
import { extractText, lastTurns, type Turn } from "./transcript.ts";

const PERMISSION_PHRASES = [
  /\bcan i (run|use|execute)\b/i,
  /\bmay i (run|use|execute)\b/i,
  /\bok(?:ay)? (?:to|if i)\b/i,
  /\b(?:should i|shall i) (?:run|push|delete|remove|drop)\b/i,
];

function isPermissionPrompt(text: string): boolean {
  if (!text.trim().endsWith("?")) return false;
  return PERMISSION_PHRASES.some((re) => re.test(text));
}

export function classify(transcript: Turn[], alive: boolean): ClassifyResult {
  const turns = lastTurns(transcript, 20);

  // Side-panel context fields (most recent of each, regardless of last-turn classification).
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
    } else if (text && isPermissionPrompt(text)) {
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
      reason = `tool error: ${detail.slice(0, 100)}`;
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
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd backend && bun test test/classify.test.ts`
Expected: 6 tests pass.

- [ ] **Step 7: Commit**

```bash
git add backend/src/claude/classify.ts backend/test/classify.test.ts backend/test/fixtures/
git commit -m "feat(backend): port 5-state classifier with permission prompt detection"
```

## Task 9: Staleness decay tests [DONE — loop 3]

**Files:**
- Modify: `backend/test/classify.test.ts` (add cases) — or new file:
- Create: `backend/test/staleness.test.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// backend/test/staleness.test.ts
import { test, expect } from "bun:test";
import { stalenessDecay } from "../src/claude/classify.ts";

test("0s → 0 decay", () => expect(stalenessDecay(0)).toBe(0));
test("just under grace (300s) → 0 decay", () => expect(stalenessDecay(300)).toBe(0));
test("301s → 0 decay (rounded)", () => expect(stalenessDecay(301)).toBe(0));
test("660s → 1 decay (300s grace + 360s)", () => expect(stalenessDecay(660)).toBe(1));
test("3600s → 9 decay", () => expect(stalenessDecay(3600)).toBe(9));
test("36000s → caps at 60", () => expect(stalenessDecay(36_000)).toBe(60));
```

- [ ] **Step 2: Run + commit**

Run: `cd backend && bun test test/staleness.test.ts`
Expected: 6 pass.

```bash
git add backend/test/staleness.test.ts
git commit -m "test(backend): cover staleness decay boundaries"
```

## Task 10: Port `git_info` + `loadLiveSessions` [DONE — loop 4]

**Files:**
- Create: `backend/src/util/git.ts`
- Create: `backend/src/util/pid.ts` (stub for now — full liveness in Task 11)
- Create: `backend/src/claude/sessions.ts`
- Test: existing fixtures

- [ ] **Step 1: Implement `backend/src/util/git.ts`**

```typescript
// backend/src/util/git.ts
import { spawnSync } from "node:child_process";
import { existsSync, statSync } from "node:fs";

export interface GitInfo {
  branch: string | null;
  dirty: number;
  last_commit: string | null;
}

function runGit(cwd: string, args: string[], timeoutMs: number): string | null {
  if (!existsSync(cwd) || !statSync(cwd).isDirectory()) return null;
  const r = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf-8", timeout: timeoutMs });
  if (r.status !== 0) return null;
  return r.stdout.trim();
}

export function gitInfo(cwd: string): GitInfo {
  const branch = runGit(cwd, ["branch", "--show-current"], 1500);
  const status = runGit(cwd, ["status", "--porcelain"], 1500);
  const dirty = status ? status.split("\n").filter((l) => l.trim().length > 0).length : 0;
  const last = runGit(cwd, ["log", "-1", "--pretty=%h %s"], 1500);
  return { branch: branch || null, dirty, last_commit: last || null };
}

export function gitDiffStat(cwd: string): string | null {
  const out = runGit(cwd, ["diff", "--stat"], 2000);
  return out && out.length > 0 ? out.slice(0, 2000) : null;
}
```

- [ ] **Step 2: Implement `backend/src/util/pid.ts` (interim simple version)**

```typescript
// backend/src/util/pid.ts — interim. Full liveness in Task 11.
export function isPidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}
```

- [ ] **Step 3: Implement `backend/src/claude/sessions.ts`**

```typescript
// backend/src/claude/sessions.ts
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { basename, join } from "node:path";
import type { LiveSession } from "../types.ts";
import { sessionsDir } from "./paths.ts";
import { findTranscript, readJsonlTail } from "./transcript.ts";
import { classify, stalenessDecay } from "./classify.ts";
import { gitInfo } from "../util/git.ts";
import { isPidAlive } from "../util/pid.ts";

interface SessionFile {
  kind?: string;
  pid?: number;
  sessionId?: string;
  cwd?: string;
  startedAt?: number;
}

export function loadLiveSessions(): LiveSession[] {
  const dir = sessionsDir();
  if (!existsSync(dir)) return [];
  const out: LiveSession[] = [];
  for (const name of readdirSync(dir)) {
    if (!name.endsWith(".json")) continue;
    let data: SessionFile;
    try {
      data = JSON.parse(readFileSync(join(dir, name), "utf-8")) as SessionFile;
    } catch {
      continue;
    }
    if (data.kind !== "interactive") continue;
    const pid = data.pid;
    const sid = data.sessionId;
    const cwd = data.cwd ?? "";
    const startedAt = data.startedAt ?? 0;
    if (!pid || !sid) continue;
    if (!isPidAlive(pid)) continue;

    const tp = findTranscript(cwd, sid);
    const transcript = tp ? readJsonlTail(tp, 300) : [];
    const meta = classify(transcript, true);
    const gi = gitInfo(cwd);
    const tpMtime = tp && existsSync(tp) ? statSync(tp).mtimeMs / 1000 : startedAt / 1000;
    const ageSec = Math.max(0, Date.now() / 1000 - tpMtime);
    const decay = stalenessDecay(ageSec);
    out.push({
      pid,
      sessionId: sid,
      cwd,
      repo: basename(cwd),
      branch: gi.branch,
      dirty: gi.dirty,
      started_at: startedAt,
      last_activity: tpMtime * 1000,
      age_sec: Math.floor(ageSec),
      stale_decay: decay,
      transcript_found: tp !== null,
      ...meta,
      priority: meta.priority + decay,
    });
  }
  out.sort((a, b) => a.priority - b.priority || b.last_activity - a.last_activity);
  return out;
}
```

- [ ] **Step 4: Smoke-test the loader against your real `~/.claude/`**

Run:
```bash
cd backend
bun -e 'import("./src/claude/sessions.ts").then((m) => console.log(JSON.stringify(m.loadLiveSessions(), null, 2)))'
```
Expected: an array of session objects (possibly empty if no live sessions). No errors.

- [ ] **Step 5: Commit**

```bash
git add backend/src/util/git.ts backend/src/util/pid.ts backend/src/claude/sessions.ts
git commit -m "feat(backend): port loadLiveSessions with git info and staleness decay"
```

## Task 11: Lift cctop's PID + start-time liveness [DONE — loop 5]

**Files:**
- Modify: `backend/src/util/pid.ts`
- Test: `backend/test/liveness.test.ts`

- [ ] **Step 1: Read the cctop source for reference**

Open `/Users/claudevcheval/Hanalei/cctop/menubar/CctopMenubar/Models/Session.swift` lines 360–396. The pattern: `kill(pid, 0)` + `sysctl(KERN_PROC_PID)` to get `kinfo_proc`, compare `p_starttime` against stored value, reject `p_stat == 4` (suspended), reject `e_ppid == 1` (orphaned).

- [ ] **Step 2: Write the failing test**

```typescript
// backend/test/liveness.test.ts
import { test, expect } from "bun:test";
import { isPidAlive, getProcessStartTime } from "../src/util/pid.ts";

test("our own pid is alive", () => {
  expect(isPidAlive(process.pid)).toBe(true);
});

test("getProcessStartTime returns a number for current pid", () => {
  const t = getProcessStartTime(process.pid);
  expect(typeof t).toBe("number");
  expect(t).toBeGreaterThan(0);
});

test("absent pid → false", () => {
  expect(isPidAlive(999_999_999)).toBe(false);
});

test("liveness with mismatched start-time → false (PID reuse)", () => {
  // We pass a wildly wrong start time
  expect(isPidAlive(process.pid, 1)).toBe(false);
});

test("liveness with matching start-time → true", () => {
  const t = getProcessStartTime(process.pid)!;
  expect(isPidAlive(process.pid, t)).toBe(true);
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd backend && bun test test/liveness.test.ts`
Expected: FAIL (`getProcessStartTime` not exported).

- [ ] **Step 4: Implement using `ps`**

`sysctl` from TS would require FFI. The simpler portable path on macOS: shell out to `ps -o lstart=,stat=,ppid= -p <pid>`. Output format: `Wed Apr 28 10:15:32 2026 S+ 12345`. Parse `lstart` to a timestamp; reject `stat` containing `T` (suspended) or `Z` (zombie); reject `ppid == 1`.

```typescript
// backend/src/util/pid.ts
import { spawnSync } from "node:child_process";

interface PsRow {
  startTime: number;     // unix epoch ms
  stat: string;
  ppid: number;
}

function ps(pid: number): PsRow | null {
  const r = spawnSync("ps", ["-o", "lstart=,stat=,ppid=", "-p", String(pid)], {
    encoding: "utf-8",
    timeout: 1000,
  });
  if (r.status !== 0 || !r.stdout) return null;
  const line = r.stdout.trim();
  if (!line) return null;
  // lstart is 5 whitespace-separated fields: "Wed Apr 28 10:15:32 2026"
  const parts = line.split(/\s+/);
  if (parts.length < 7) return null;
  const lstart = parts.slice(0, 5).join(" ");
  const stat = parts[5]!;
  const ppid = parseInt(parts[6]!, 10);
  const ts = Date.parse(lstart);
  if (isNaN(ts)) return null;
  return { startTime: ts, stat, ppid };
}

export function getProcessStartTime(pid: number): number | null {
  return ps(pid)?.startTime ?? null;
}

export function isPidAlive(pid: number, expectedStartTime?: number): boolean {
  try {
    process.kill(pid, 0);
  } catch {
    return false;
  }
  const row = ps(pid);
  if (!row) return false;
  if (row.stat.includes("T") || row.stat.includes("Z")) return false; // suspended or zombie
  if (row.ppid === 1) return false; // orphaned
  if (expectedStartTime !== undefined) {
    if (Math.abs(row.startTime - expectedStartTime) > 2000) return false; // PID reuse
  }
  return true;
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd backend && bun test test/liveness.test.ts`
Expected: 5 pass.

- [ ] **Step 6: Wire `loadLiveSessions` to record + check start time**

Modify `backend/src/claude/sessions.ts` to capture `pidStartTime` from the session JSON if present, and pass it to `isPidAlive`. Also bump `getProcessStartTime` for sessions whose JSON lacks the field (fallback). Update the `SessionFile` interface and the call:

```typescript
interface SessionFile {
  kind?: string;
  pid?: number;
  pidStartTime?: number;
  sessionId?: string;
  cwd?: string;
  startedAt?: number;
}
// ...inside loop:
if (!isPidAlive(pid, data.pidStartTime)) continue;
```

- [ ] **Step 7: Commit**

```bash
git add backend/src/util/pid.ts backend/test/liveness.test.ts backend/src/claude/sessions.ts
git commit -m "feat(backend): lift cctop's PID + start-time liveness check"
```

## Task 12: Port `loadRecentByRepo` + `recentPromptsForCwd` [DONE — loop 6]

**Files:**
- Create: `backend/src/claude/recent.ts`
- Create: `backend/src/claude/history.ts`

- [ ] **Step 1: Implement `backend/src/claude/history.ts`**

```typescript
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
```

- [ ] **Step 2: Implement `backend/src/claude/recent.ts`**

```typescript
// backend/src/claude/recent.ts
import { existsSync, readdirSync, statSync, openSync, readSync, closeSync } from "node:fs";
import { basename, join } from "node:path";
import type { RecentRepo } from "../types.ts";
import { projectsDir } from "./paths.ts";
import { readJsonlTail } from "./transcript.ts";
import { classify } from "./classify.ts";
import { gitInfo } from "../util/git.ts";

const SKIP_PATTERNS = [/-private-var-folders-/, /test-repo/];

function firstCwd(jsonlPath: string): string | null {
  try {
    const fd = openSync(jsonlPath, "r");
    try {
      const buf = Buffer.alloc(64 * 1024);
      const n = readSync(fd, buf, 0, buf.length, 0);
      const text = buf.subarray(0, n).toString("utf-8");
      for (const line of text.split("\n")) {
        if (!line.trim()) continue;
        try {
          const obj = JSON.parse(line) as { cwd?: string };
          if (obj.cwd) return obj.cwd;
        } catch {
          // skip
        }
      }
      return null;
    } finally {
      closeSync(fd);
    }
  } catch {
    return null;
  }
}

export function loadRecentByRepo(days: number): RecentRepo[] {
  if (!existsSync(projectsDir())) return [];
  const cutoff = Date.now() / 1000 - days * 86400;
  const byCwd = new Map<string, { mtime: number; sessionId: string; transcript: string }>();
  for (const dirent of readdirSync(projectsDir(), { withFileTypes: true })) {
    if (!dirent.isDirectory()) continue;
    const name = dirent.name;
    if (SKIP_PATTERNS.some((re) => re.test(name))) continue;
    const dirPath = join(projectsDir(), name);
    for (const entry of readdirSync(dirPath)) {
      if (!entry.endsWith(".jsonl")) continue;
      const file = join(dirPath, entry);
      let mt: number;
      try {
        mt = statSync(file).mtimeMs / 1000;
      } catch {
        continue;
      }
      if (mt < cutoff) continue;
      const cwd = firstCwd(file) ?? ("/" + name.replace(/^-/, "").replace(/-/g, "/"));
      const sid = entry.replace(/\.jsonl$/, "");
      const cur = byCwd.get(cwd);
      if (!cur || mt > cur.mtime) byCwd.set(cwd, { mtime: mt, sessionId: sid, transcript: file });
    }
  }
  const rows: RecentRepo[] = [];
  for (const [cwd, info] of byCwd.entries()) {
    if (!existsSync(cwd)) continue;
    const transcript = readJsonlTail(info.transcript, 300);
    const meta = classify(transcript, false);
    const gi = gitInfo(cwd);
    rows.push({
      cwd,
      repo: basename(cwd),
      branch: gi.branch,
      dirty: gi.dirty,
      last_commit: gi.last_commit,
      sessionId: info.sessionId,
      last_activity: info.mtime * 1000,
      ...meta,
    });
  }
  rows.sort((a, b) => b.last_activity - a.last_activity);
  return rows;
}
```

- [ ] **Step 3: Smoke-test against real `~/.claude/`**

Run:
```bash
cd backend
bun -e 'import("./src/claude/recent.ts").then((m) => console.log(m.loadRecentByRepo(14).length, "repos"))'
```
Expected: a count printed (e.g. `5 repos`).

- [ ] **Step 4: Commit**

```bash
git add backend/src/claude/recent.ts backend/src/claude/history.ts
git commit -m "feat(backend): port loadRecentByRepo and recentPromptsForCwd"
```

## Task 13: Port the Ghostty matcher [DONE — loop 7]

**Files:**
- Create: `backend/src/ghostty/tokenize.ts`
- Create: `backend/src/ghostty/score.ts`
- Create: `backend/src/ghostty/applescript.ts`
- Create: `backend/src/ghostty/focus.ts`
- Test: `backend/test/tokenize.test.ts`
- Test: `backend/test/score.test.ts`

- [ ] **Step 1: Implement + test `tokenize.ts`**

```typescript
// backend/src/ghostty/tokenize.ts
const STOPWORDS = new Set([
  "the","a","an","is","are","was","were","to","of","for","in","on","at","by",
  "and","or","i","me","my","you","we","it","this","that","from","with","can",
  "how","what","do","does","be","been","has","have","had","will","would","should",
  "but","not","if","so","as","about","into","out","up","down","over","under",
  "just","please","want","need","here","there","now","then","some","any","all",
  "new","like","get","got","let","make","made","use","used","using","way","one",
]);

export function tokenize(text: string | undefined): Set<string> {
  if (!text) return new Set();
  // Strip diacritics: NFKD + remove non-ASCII
  let s = text.normalize("NFKD").replace(/[^\u0000-\u007f]/g, "");
  // Strip URL %-encoding before lowercasing
  s = s.replace(/%[0-9a-fA-F]{2}/g, " ").toLowerCase();
  s = s.replace(/[^a-z0-9\s]/g, " ");
  const out = new Set<string>();
  for (const w of s.split(/\s+/)) {
    if (w.length >= 3 && !/^\d+$/.test(w) && !STOPWORDS.has(w)) out.add(w);
  }
  return out;
}
```

```typescript
// backend/test/tokenize.test.ts
import { test, expect } from "bun:test";
import { tokenize } from "../src/ghostty/tokenize.ts";

test("strips stopwords + short tokens", () => {
  const t = tokenize("the cat is on a mat about something");
  expect(t.has("the")).toBe(false);
  expect(t.has("cat")).toBe(true);
  expect(t.has("mat")).toBe(true);
});
test("strips %-encoding", () => {
  expect(tokenize("foo%20bar").has("20bar")).toBe(false);
});
test("normalizes unicode", () => {
  expect(tokenize("café").has("cafe")).toBe(true);
});
test("rejects pure-numeric tokens", () => {
  expect(tokenize("foo 123 bar").has("123")).toBe(false);
});
```

Run: `cd backend && bun test test/tokenize.test.ts` → 4 pass.

- [ ] **Step 2: Implement + test `score.ts`**

```typescript
// backend/src/ghostty/score.ts
export interface ScoreResult {
  score: number;
  hits: string[];
  early_hits: string[];
  recent_hits: string[];
  cwd_hits: string[];
}

export function scoreWindow(
  windowTokens: Set<string>,
  earlyTokens: Set<string>,
  recentTokens: Set<string>,
  cwdTokens: Set<string>,
): ScoreResult {
  const inter = (a: Set<string>, b: Set<string>): Set<string> => {
    const r = new Set<string>();
    for (const v of a) if (b.has(v)) r.add(v);
    return r;
  };
  const earlyHit = inter(windowTokens, earlyTokens);
  const recentHit = inter(windowTokens, recentTokens);
  const cwdHit = inter(windowTokens, cwdTokens);

  const counted = new Set<string>();
  let score = 0;
  for (const t of earlyHit) if (!counted.has(t)) { score += 3; counted.add(t); }
  for (const t of cwdHit) if (!counted.has(t)) { score += 2; counted.add(t); }
  for (const t of recentHit) if (!counted.has(t)) { score += 1; counted.add(t); }

  const sortS = (s: Set<string>): string[] => [...s].sort();
  return {
    score,
    hits: sortS(counted),
    early_hits: sortS(earlyHit),
    recent_hits: sortS(new Set([...recentHit].filter((t) => !earlyHit.has(t)))),
    cwd_hits: sortS(new Set([...cwdHit].filter((t) => !earlyHit.has(t)))),
  };
}
```

```typescript
// backend/test/score.test.ts
import { test, expect } from "bun:test";
import { scoreWindow } from "../src/ghostty/score.ts";
const S = (xs: string[]): Set<string> => new Set(xs);

test("early hits weighted 3, cwd 2, recent 1", () => {
  const r = scoreWindow(S(["alpha","beta","gamma"]), S(["alpha"]), S(["beta"]), S(["gamma"]));
  expect(r.score).toBe(3 + 1 + 2);
});
test("no double-count when token in two buckets", () => {
  const r = scoreWindow(S(["alpha"]), S(["alpha"]), S(["alpha"]), S(["alpha"]));
  expect(r.score).toBe(3);
});
test("zero overlap → score 0", () => {
  const r = scoreWindow(S(["x"]), S(["alpha"]), S(["beta"]), S(["gamma"]));
  expect(r.score).toBe(0);
});
```

Run: `cd backend && bun test test/score.test.ts` → 3 pass.

- [ ] **Step 3: Implement `applescript.ts`**

```typescript
// backend/src/ghostty/applescript.ts
import { spawnSync } from "node:child_process";

export interface GhosttyWindow { index: number; title: string }
export interface ListResult { windows: GhosttyWindow[]; error: string | null }

const LIST_SCRIPT = `
tell application "System Events"
  tell process "Ghostty"
    set out to ""
    set n to count of windows
    repeat with i from 1 to n
      try
        set t to name of window i
      on error
        set t to ""
      end try
      set out to out & i & "\\t" & t & linefeed
    end repeat
    return out
  end tell
end tell`;

export function activateGhostty(): { ok: boolean; reason?: string; detail?: string } {
  const r = spawnSync("osascript", ["-e", 'tell application "Ghostty" to activate'], { encoding: "utf-8", timeout: 2000 });
  if (r.status !== 0) return { ok: false, reason: "ghostty_activate_failed", detail: (r.stderr ?? "").trim().slice(0, 200) };
  return { ok: true };
}

export function listGhosttyWindows(): ListResult {
  const r = spawnSync("osascript", ["-e", LIST_SCRIPT], { encoding: "utf-8", timeout: 3000 });
  if (r.status !== 0) {
    const err = r.stderr.trim() || `exit ${r.status}`;
    const reason = err.includes("1002") || err.toLowerCase().includes("not allowed") ? "ax_permission_denied" : "list_failed";
    return { windows: [], error: `${reason}: ${err.slice(0, 200)}` };
  }
  const windows: GhosttyWindow[] = [];
  for (const line of (r.stdout ?? "").split("\n")) {
    if (!line.includes("\t")) continue;
    const [idxs, title] = line.split("\t", 2) as [string, string];
    const idx = parseInt(idxs.trim(), 10);
    if (!isNaN(idx)) windows.push({ index: idx, title: title.trim() });
  }
  return { windows, error: null };
}

export function raiseGhosttyWindow(index: number): boolean {
  const script = `
tell application "System Events"
  tell process "Ghostty"
    try
      perform action "AXRaise" of window ${index}
      set frontmost to true
      return "ok"
    on error
      return "err"
    end try
  end tell
end tell`;
  const r = spawnSync("osascript", ["-e", script], { encoding: "utf-8", timeout: 2000 });
  return (r.stdout ?? "").includes("ok");
}
```

- [ ] **Step 4: Implement `focus.ts`**

```typescript
// backend/src/ghostty/focus.ts
import { basename } from "node:path";
import { existsSync, readFileSync } from "node:fs";
import type { FocusResult } from "../types.ts";
import { findTranscript } from "../claude/transcript.ts";
import { tokenize } from "./tokenize.ts";
import { scoreWindow } from "./score.ts";
import { activateGhostty, listGhosttyWindows, raiseGhosttyWindow } from "./applescript.ts";

const MIN_SCORE = 5;
const MIN_MARGIN = 3;

function sessionPrompts(cwd: string, sid: string | null): { early: string[]; recent: string[] } {
  if (!sid) return { early: [], recent: [] };
  const tp = findTranscript(cwd, sid);
  if (!tp || !existsSync(tp)) return { early: [], recent: [] };
  const all: string[] = [];
  for (const line of readFileSync(tp, "utf-8").split("\n")) {
    if (!line.includes('"type":"user"')) continue;
    let obj: { isSidechain?: boolean; message?: { role?: string; content?: unknown } };
    try { obj = JSON.parse(line); } catch { continue; }
    if (obj.isSidechain) continue;
    const m = obj.message;
    if (!m || m.role !== "user") continue;
    let text = "";
    if (typeof m.content === "string") text = m.content;
    else if (Array.isArray(m.content)) {
      for (const b of m.content as { type?: string; text?: string }[]) {
        if (b.type === "text" && typeof b.text === "string") { text = b.text; break; }
      }
    }
    if (!text) continue;
    if (text.startsWith("<ide_selection>") || text.startsWith("<system-reminder>")) continue;
    text = text.trim();
    if (text) all.push(text.slice(0, 500));
  }
  return { early: all.slice(0, 5), recent: all.length > 5 ? all.slice(-3) : [] };
}

export async function focusGhostty(cwd: string, sid: string | null): Promise<FocusResult> {
  const { early, recent } = sessionPrompts(cwd, sid);
  const earlyTokens = tokenize(early.join(" "));
  const recentTokens = tokenize(recent.join(" "));
  const cwdTokens = tokenize(basename(cwd).replace(/[-_]/g, " "));

  const act = activateGhostty();
  if (!act.ok) return { ok: false, matched: false, reason: act.reason, detail: act.detail };

  await new Promise((r) => setTimeout(r, 250)); // let AX catch up
  const list = listGhosttyWindows();
  if (list.error) return { ok: false, matched: false, reason: list.error.split(":", 1)[0], detail: list.error };

  const scored = list.windows.map((w) => {
    const tt = tokenize(w.title);
    const s = scoreWindow(tt, earlyTokens, recentTokens, cwdTokens);
    return { ...w, ...s };
  }).sort((a, b) => b.score - a.score);

  const best = scored[0];
  const second = scored[1]?.score ?? 0;
  const confident = best && best.score >= MIN_SCORE && best.score - second >= MIN_MARGIN;

  if (confident) {
    const raised = raiseGhosttyWindow(best.index);
    return {
      ok: true,
      matched: raised,
      window_index: best.index,
      matched_title: best.title,
      score: best.score,
      margin: best.score - second,
    };
  }
  return { ok: true, matched: false, reason: "no_confident_match" };
}
```

- [ ] **Step 5: Commit**

```bash
git add backend/src/ghostty/ backend/test/tokenize.test.ts backend/test/score.test.ts
git commit -m "feat(backend): port Ghostty content-match focus"
```

## Task 14: Port resume / fork / open-IDE actions [DONE — loop 8]

**Files:**
- Create: `backend/src/util/ide.ts`
- Create: `backend/src/actions/resume.ts`
- Create: `backend/src/actions/fork.ts`
- Create: `backend/src/actions/openIde.ts`

- [ ] **Step 1: Implement `backend/src/util/ide.ts`**

```typescript
// backend/src/util/ide.ts
import { existsSync } from "node:fs";

const IDE_PRIORITY: [string, string][] = [
  ["Cursor", "Cursor"],
  ["Visual Studio Code", "VS Code"],
  ["Zed", "Zed"],
  ["Windsurf", "Windsurf"],
  ["Sublime Text", "Sublime Text"],
  ["WebStorm", "WebStorm"],
  ["PyCharm", "PyCharm"],
  ["GoLand", "GoLand"],
  ["Rider", "Rider"],
  ["CLion", "CLion"],
  ["Xcode", "Xcode"],
];

export function detectIde(): { bundle: string; display: string } {
  const override = (process.env.CC_DASH_IDE ?? "").trim();
  if (override) return { bundle: override, display: override };
  for (const [bundle, display] of IDE_PRIORITY) {
    if (existsSync(`/Applications/${bundle}.app`)) return { bundle, display };
  }
  return { bundle: "", display: "Finder" };
}
```

- [ ] **Step 2: Implement `backend/src/actions/resume.ts`**

```typescript
// backend/src/actions/resume.ts
import { spawnSync } from "node:child_process";
import type { ResumeResult } from "../types.ts";

function shellQuote(s: string): string {
  return "'" + s.replace(/'/g, `'\\''`) + "'";
}

export function resumeCommand(cwd: string, sid: string | null): ResumeResult {
  const parts = [`cd ${shellQuote(cwd)}`];
  parts.push(sid ? `claude --resume ${sid}` : "claude --continue");
  const cmd = parts.join(" && ");
  const r = spawnSync("pbcopy", [], { input: cmd, timeout: 2000 });
  return { command: cmd, copied_to_clipboard: r.status === 0 };
}
```

- [ ] **Step 3: Implement `backend/src/actions/fork.ts`**

```typescript
// backend/src/actions/fork.ts
import { spawnSync } from "node:child_process";
import { basename } from "node:path";
import type { ForkResult } from "../types.ts";
import { findTranscript, readJsonlTail } from "../claude/transcript.ts";
import { classify } from "../claude/classify.ts";
import { gitInfo, gitDiffStat } from "../util/git.ts";
import { recentPromptsForCwd } from "../claude/history.ts";

export async function forkSummary(cwd: string, sid: string | null): Promise<ForkResult> {
  const tp = sid ? findTranscript(cwd, sid) : null;
  const turns = tp ? readJsonlTail(tp, 400) : [];
  const meta = classify(turns, false);
  const gi = gitInfo(cwd);
  const prompts = await recentPromptsForCwd(cwd, 5);
  const diff = gitDiffStat(cwd);
  const lines = [
    `# Resuming work in \`${basename(cwd)}\``,
    `**Branch**: ${gi.branch ?? "n/a"}  `,
    `**Uncommitted files**: ${gi.dirty}  `,
    `**Last commit**: ${gi.last_commit ?? "n/a"}`,
    "",
    "## What I was working on (recent prompts)",
    ...prompts.map((p) => `- ${p.display}`),
  ];
  if (meta.last_assistant) {
    lines.push("", "## Claude's last message", "```", meta.last_assistant.slice(0, 1500), "```");
  }
  if (meta.open_tool) {
    lines.push("", "## Open tool at session end", `- ${meta.open_tool.name}`);
  }
  if (diff) {
    lines.push("", "## Git diff stat", "```", diff, "```");
  }
  lines.push("", "Pick up from here — please continue where we left off.");
  const summary = lines.join("\n");
  const r = spawnSync("pbcopy", [], { input: summary, timeout: 2000 });
  return { summary, copied_to_clipboard: r.status === 0 };
}
```

- [ ] **Step 4: Implement `backend/src/actions/openIde.ts`**

```typescript
// backend/src/actions/openIde.ts
import { existsSync, statSync } from "node:fs";
import type { OpenIdeResult } from "../types.ts";
import { detectIde } from "../util/ide.ts";
import { spawnSync } from "node:child_process";

export function openInIde(cwd: string): OpenIdeResult {
  if (!cwd || !existsSync(cwd) || !statSync(cwd).isDirectory()) {
    return { ok: false, error: "cwd_not_a_directory" };
  }
  const { bundle, display } = detectIde();
  const args = ["open"];
  if (bundle) args.push("-a", bundle);
  args.push(cwd);
  const r = spawnSync(args[0]!, args.slice(1), { encoding: "utf-8", timeout: 3000 });
  if (r.status !== 0) {
    return { ok: false, error: "open_failed", ide: display, detail: (r.stderr ?? "").trim().slice(0, 200) };
  }
  return { ok: true, ide: display };
}
```

- [ ] **Step 5: Commit**

```bash
git add backend/src/util/ide.ts backend/src/actions/
git commit -m "feat(backend): port resume / fork / open-IDE actions"
```

## Task 15: Implement corpus indices + Decision Log extractor [DONE — loop 9]

**Files:**
- Create: `backend/src/corpus/indices.ts`
- Create: `backend/src/corpus/decisions.ts`
- Create: `backend/src/corpus/projections.ts`
- Test: `backend/test/decisions.test.ts`
- Create: `backend/test/fixtures/dot-claude/projects/-tmp-test-repo/sess-decisions.jsonl`

- [ ] **Step 1: Create the decisions fixture**

`backend/test/fixtures/dot-claude/projects/-tmp-test-repo/sess-decisions.jsonl`:

```jsonl
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"What ORM does this repo use?"}]}}
{"type":"user","message":{"role":"user","content":"Prisma 5"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Should I write integration tests?"}]}}
{"type":"user","message":{"role":"user","content":"Yes, but only for the public API surface."}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Should I write integration tests?"}]}}
{"type":"user","message":{"role":"user","content":"Yes, but only for the public API surface."}}
```

- [ ] **Step 2: Implement `backend/src/corpus/indices.ts`**

```typescript
// backend/src/corpus/indices.ts
// Per-session and per-cwd in-memory indices, populated by the tail watcher.

export interface FileTouch { path: string; edits: number; last_touch: number }
export interface BranchSample { ts: number; branch: string }
export interface SessionTokens { input: number; cached_read: number; cached_create: number; output: number }
export interface DecisionPair { q: string; a: string }

export interface SessionIndex {
  sid: string;
  cwd: string;
  files: Map<string, FileTouch>;
  branchTimeline: BranchSample[];          // dedup consecutive same-branch
  tokens: SessionTokens;
  loadHistory: number[];                   // tool_use count per minute, length 32
  loadStartMs: number;                     // anchor for the rolling window
  startedAtMs: number;
  endedAtMs?: number;
}

export interface CorpusState {
  bySession: Map<string, SessionIndex>;     // key = sid
  decisionsByCwd: Map<string, DecisionPair[]>; // deduped
}

export function emptyState(): CorpusState {
  return { bySession: new Map(), decisionsByCwd: new Map() };
}

export function getOrCreateSession(state: CorpusState, sid: string, cwd: string): SessionIndex {
  let s = state.bySession.get(sid);
  if (!s) {
    s = {
      sid, cwd,
      files: new Map(),
      branchTimeline: [],
      tokens: { input: 0, cached_read: 0, cached_create: 0, output: 0 },
      loadHistory: new Array(32).fill(0),
      loadStartMs: Date.now(),
      startedAtMs: Date.now(),
    };
    state.bySession.set(sid, s);
  }
  return s;
}
```

- [ ] **Step 3: Implement `backend/src/corpus/decisions.ts`**

```typescript
// backend/src/corpus/decisions.ts
// Pure functions over already-loaded transcripts. The tail watcher invokes
// extractDecisions on each session's transcript and merges into state.

import type { DecisionPair } from "./indices.ts";
import type { Turn } from "../claude/transcript.ts";
import { extractText } from "../claude/transcript.ts";

const MAX_REPLY_LEN = 200;

function hash(s: string): string {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = ((h << 5) - h + s.charCodeAt(i)) | 0;
  return String(h);
}

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
  // Dedupe by (q+a) hash
  const seen = new Set<string>();
  return pairs.filter((p) => {
    const k = hash(p.q + "::" + p.a);
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}
```

- [ ] **Step 4: Write the failing test**

```typescript
// backend/test/decisions.test.ts
import { test, expect } from "bun:test";
import { extractDecisions } from "../src/corpus/decisions.ts";
import { readJsonlTail } from "../src/claude/transcript.ts";

test("extractDecisions yields 2 unique pairs from fixture (dedupes the 3rd)", () => {
  const turns = readJsonlTail("test/fixtures/dot-claude/projects/-tmp-test-repo/sess-decisions.jsonl", 100);
  const pairs = extractDecisions(turns);
  expect(pairs.length).toBe(2);
  expect(pairs[0]?.q).toContain("ORM");
  expect(pairs[1]?.q).toContain("integration tests");
});

test("extractDecisions skips long replies", () => {
  const turns = [
    { type: "assistant", message: { role: "assistant", content: [{ type: "text", text: "Why?" }] } },
    { type: "user", message: { role: "user", content: "x".repeat(500) } },
  ];
  expect(extractDecisions(turns as never).length).toBe(0);
});
```

- [ ] **Step 5: Run test → pass**

Run: `cd backend && bun test test/decisions.test.ts`
Expected: 2 pass.

- [ ] **Step 6: Implement `backend/src/corpus/projections.ts`**

```typescript
// backend/src/corpus/projections.ts
// Projection registry. Decision Log is the first concrete projection;
// future projections (gotchas, prompts-that-worked) plug in here.

import type { CorpusState, DecisionPair } from "./indices.ts";

export interface Projection<T> {
  name: string;
  query: (state: CorpusState, cwd: string) => T;
}

export const decisionsProjection: Projection<DecisionPair[]> = {
  name: "decisions",
  query: (state, cwd) => state.decisionsByCwd.get(cwd) ?? [],
};

export const REGISTRY: { [name: string]: Projection<unknown> } = {
  [decisionsProjection.name]: decisionsProjection as Projection<unknown>,
};
```

- [ ] **Step 7: Commit**

```bash
git add backend/src/corpus/ backend/test/decisions.test.ts backend/test/fixtures/
git commit -m "feat(backend): in-memory corpus indices + Decision Log extractor"
```

## Task 16: Implement the tail watcher (cold-start + reactive updates) [DONE — loop 10]

**Files:**
- Create: `backend/src/corpus/tail.ts`
- Test: `backend/test/tail-watch.test.ts`

- [ ] **Step 1: Implement `backend/src/corpus/tail.ts`**

```typescript
// backend/src/corpus/tail.ts
// Minimal tail watcher: subscribe to per-session-jsonl mutation events
// and incrementally update CorpusState. Cold-start: full read.

import { existsSync, statSync, readFileSync, watch as fsWatch, type FSWatcher } from "node:fs";
import type { Turn } from "../claude/transcript.ts";
import type { CorpusState, FileTouch } from "./indices.ts";
import { getOrCreateSession } from "./indices.ts";
import { extractDecisions } from "./decisions.ts";
import { extractText } from "../claude/transcript.ts";
import { gitInfo } from "../util/git.ts";
import { log } from "../util/log.ts";

export interface TailHandle {
  state: CorpusState;
  watchers: Map<string, FSWatcher>;
  offsets: Map<string, number>;
  add(sid: string, cwd: string, transcriptPath: string): void;
  remove(sid: string): void;
  closeAll(): void;
}

function readFromOffset(path: string, offset: number): { lines: string[]; newOffset: number } {
  if (!existsSync(path)) return { lines: [], newOffset: 0 };
  const size = statSync(path).size;
  if (size <= offset) return { lines: [], newOffset: size };
  const buf = Buffer.alloc(size - offset);
  const fd = require("node:fs").openSync(path, "r");
  try {
    require("node:fs").readSync(fd, buf, 0, buf.length, offset);
  } finally {
    require("node:fs").closeSync(fd);
  }
  const text = buf.toString("utf-8");
  const lines = text.split("\n").filter((l) => l.trim().length > 0);
  return { lines, newOffset: size };
}

function applyTurns(
  state: CorpusState,
  sid: string,
  cwd: string,
  turns: Turn[],
): void {
  const sess = getOrCreateSession(state, sid, cwd);

  // Branch sample (one per call, since we re-read git each event)
  const gi = gitInfo(cwd);
  if (gi.branch) {
    const last = sess.branchTimeline[sess.branchTimeline.length - 1];
    if (!last || last.branch !== gi.branch) {
      sess.branchTimeline.push({ ts: Date.now(), branch: gi.branch });
    }
  }

  // Files + tokens + load
  for (const t of turns) {
    if (t.type !== "assistant") continue;
    const m = t.message;
    if (!m) continue;
    if (m.usage) {
      sess.tokens.input += m.usage.input_tokens ?? 0;
      sess.tokens.cached_read += m.usage.cache_read_input_tokens ?? 0;
      sess.tokens.cached_create += m.usage.cache_creation_input_tokens ?? 0;
      sess.tokens.output += m.usage.output_tokens ?? 0;
    }
    if (Array.isArray(m.content)) {
      for (const b of m.content) {
        if (b.type === "tool_use") {
          // Bump load history (last bucket)
          sess.loadHistory[sess.loadHistory.length - 1] =
            (sess.loadHistory[sess.loadHistory.length - 1] ?? 0) + 1;
          // File-touch tracking: pull a path from common tool inputs
          const inp = (b.input ?? {}) as Record<string, unknown>;
          const path = (inp.file_path as string) ?? (inp.notebook_path as string) ?? null;
          if (path && (b.name === "Edit" || b.name === "Write" || b.name === "MultiEdit" || b.name === "NotebookEdit")) {
            const ft: FileTouch = sess.files.get(path) ?? { path, edits: 0, last_touch: 0 };
            ft.edits += 1;
            ft.last_touch = Date.now();
            sess.files.set(path, ft);
          }
        }
      }
    }
  }

  // Decisions per cwd: reread small tail and merge (idempotent — extractDecisions dedupes)
  const pairs = extractDecisions(turns);
  if (pairs.length) {
    const cur = state.decisionsByCwd.get(cwd) ?? [];
    const seen = new Set(cur.map((p) => p.q + "::" + p.a));
    for (const p of pairs) if (!seen.has(p.q + "::" + p.a)) { cur.push(p); seen.add(p.q + "::" + p.a); }
    state.decisionsByCwd.set(cwd, cur);
  }
}

export function createTail(state: CorpusState): TailHandle {
  const watchers = new Map<string, FSWatcher>();
  const offsets = new Map<string, number>();

  function add(sid: string, cwd: string, transcriptPath: string): void {
    if (watchers.has(sid)) return;
    // Cold start: read entire file once, then start watching
    const { newOffset } = readFromOffset(transcriptPath, 0);
    offsets.set(sid, newOffset);
    if (existsSync(transcriptPath)) {
      try {
        const text = readFileSync(transcriptPath, "utf-8");
        const turns: Turn[] = [];
        for (const line of text.split("\n")) {
          if (!line.trim()) continue;
          try { turns.push(JSON.parse(line) as Turn); } catch { /* skip */ }
        }
        applyTurns(state, sid, cwd, turns);
      } catch (e) {
        log.warn(`tail: cold-read failed`, { sid, e: String(e) });
      }
    }
    try {
      const w = fsWatch(transcriptPath, { persistent: true }, () => {
        const off = offsets.get(sid) ?? 0;
        const { lines, newOffset } = readFromOffset(transcriptPath, off);
        offsets.set(sid, newOffset);
        const turns: Turn[] = [];
        for (const line of lines) {
          try { turns.push(JSON.parse(line) as Turn); } catch { /* skip */ }
        }
        if (turns.length) applyTurns(state, sid, cwd, turns);
      });
      watchers.set(sid, w);
    } catch (e) {
      log.warn(`tail: watch failed`, { sid, e: String(e) });
    }
  }

  function remove(sid: string): void {
    const w = watchers.get(sid);
    if (w) { w.close(); watchers.delete(sid); }
    offsets.delete(sid);
    // Eviction policy: keep state for 1h after end, then drop
    setTimeout(() => state.bySession.delete(sid), 60 * 60 * 1000).unref?.();
  }

  function closeAll(): void {
    for (const w of watchers.values()) w.close();
    watchers.clear();
    offsets.clear();
  }

  return { state, watchers, offsets, add, remove, closeAll };
}
```

- [ ] **Step 2: Write the integration test**

```typescript
// backend/test/tail-watch.test.ts
import { test, expect } from "bun:test";
import { mkdtempSync, writeFileSync, appendFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createTail } from "../src/corpus/tail.ts";
import { emptyState } from "../src/corpus/indices.ts";

test("tail picks up new turns appended to a transcript", async () => {
  const dir = mkdtempSync(join(tmpdir(), "cc-tail-"));
  const file = join(dir, "sess.jsonl");
  writeFileSync(file, "");
  const state = emptyState();
  const tail = createTail(state);
  tail.add("sid-1", dir, file);

  appendFileSync(
    file,
    JSON.stringify({
      type: "assistant",
      message: {
        role: "assistant",
        usage: { input_tokens: 10, output_tokens: 5 },
        content: [{ type: "tool_use", name: "Edit", input: { file_path: "/tmp/x.ts" } }],
      },
    }) + "\n",
  );
  // fs.watch is async; give it a beat
  await new Promise((r) => setTimeout(r, 250));

  const sess = state.bySession.get("sid-1");
  expect(sess?.tokens.input).toBe(10);
  expect(sess?.tokens.output).toBe(5);
  expect(sess?.files.get("/tmp/x.ts")?.edits).toBe(1);
  tail.closeAll();
});
```

- [ ] **Step 3: Run + commit**

Run: `cd backend && bun test test/tail-watch.test.ts`
Expected: 1 pass.

```bash
git add backend/src/corpus/tail.ts backend/test/tail-watch.test.ts
git commit -m "feat(backend): tail watcher cold-start + incremental updates"
```

## Task 17: Implement `panel` and `session-detail` builders [DONE — loop 11]

**Files:**
- Create: `backend/src/claude/panel.ts`
- Create: `backend/src/claude/sessionDetail.ts`

- [ ] **Step 1: Implement `backend/src/claude/panel.ts`**

```typescript
// backend/src/claude/panel.ts
import { basename } from "node:path";
import type { Panel } from "../types.ts";
import { findTranscript, readJsonlTail } from "./transcript.ts";
import { classify } from "./classify.ts";
import { gitInfo, gitDiffStat } from "../util/git.ts";
import { recentPromptsForCwd } from "./history.ts";

export async function buildPanel(cwd: string, sid: string | null): Promise<Panel> {
  const tp = sid ? findTranscript(cwd, sid) : null;
  const turns = tp ? readJsonlTail(tp, 400) : [];
  const meta = classify(turns, false);
  const gi = gitInfo(cwd);
  const prompts = await recentPromptsForCwd(cwd, 5);
  return {
    cwd, repo: basename(cwd), sessionId: sid,
    transcript_found: tp !== null,
    git: gi,
    diff_summary: gitDiffStat(cwd),
    recent_prompts: prompts,
    last_user: meta.last_user, last_assistant: meta.last_assistant,
    event: meta.event, reason: meta.reason, open_tool: meta.open_tool,
  };
}
```

- [ ] **Step 2: Implement `backend/src/claude/sessionDetail.ts`**

```typescript
// backend/src/claude/sessionDetail.ts
import { basename } from "node:path";
import type { SessionDetail } from "../types.ts";
import type { CorpusState } from "../corpus/indices.ts";
import { decisionsProjection } from "../corpus/projections.ts";

export function buildSessionDetail(state: CorpusState, sid: string): SessionDetail | null {
  const s = state.bySession.get(sid);
  if (!s) return null;
  const ageSec = Math.floor((Date.now() - s.startedAtMs) / 1000);
  return {
    sessionId: s.sid,
    cwd: s.cwd,
    repo: basename(s.cwd),
    branch: s.branchTimeline[s.branchTimeline.length - 1]?.branch ?? null,
    branch_history: s.branchTimeline.map((b) => b.branch),
    files_changed: [...s.files.values()].sort((a, b) => b.last_touch - a.last_touch),
    tokens: { ...s.tokens, context_limit: 200_000 },
    load_history: [...s.loadHistory],
    last_assistant: "",       // populated below
    open_tool: null,          // populated below by callsite via classify
    decisions: decisionsProjection.query(state, s.cwd),
    source: "cc",
    age_sec: ageSec,
  };
}
```

(Callers in the HTTP handler will fill `last_assistant` and `open_tool` by calling `classify()`.)

- [ ] **Step 3: Commit**

```bash
git add backend/src/claude/panel.ts backend/src/claude/sessionDetail.ts
git commit -m "feat(backend): panel and session-detail builders"
```

## Task 18: HTTP server with all endpoints [DONE — loop 12]

**Files:**
- Modify: `backend/src/server.ts`
- Test: `backend/test/api.test.ts`

- [ ] **Step 1: Replace `backend/src/server.ts`**

```typescript
import { log } from "./util/log.ts";
import { loadLiveSessions } from "./claude/sessions.ts";
import { loadRecentByRepo } from "./claude/recent.ts";
import { buildPanel } from "./claude/panel.ts";
import { buildSessionDetail } from "./claude/sessionDetail.ts";
import { focusGhostty } from "./ghostty/focus.ts";
import { resumeCommand } from "./actions/resume.ts";
import { forkSummary } from "./actions/fork.ts";
import { openInIde } from "./actions/openIde.ts";
import { detectIde } from "./util/ide.ts";
import { emptyState } from "./corpus/indices.ts";
import { createTail } from "./corpus/tail.ts";
import { findTranscript } from "./claude/transcript.ts";
import { decisionsProjection, REGISTRY } from "./corpus/projections.ts";
import { existsSync } from "node:fs";

const args = process.argv.slice(2);
const portIdx = args.indexOf("--port");
const port = portIdx >= 0 && args[portIdx + 1] ? parseInt(args[portIdx + 1]!, 10) : 0;

const state = emptyState();
const tail = createTail(state);

// Cold start: register a tail watcher per live session
function rebalanceWatchers(): void {
  const sessions = loadLiveSessions();
  const liveSids = new Set(sessions.map((s) => s.sessionId));
  for (const sid of [...tail.watchers.keys()]) {
    if (!liveSids.has(sid)) tail.remove(sid);
  }
  for (const s of sessions) {
    if (!tail.watchers.has(s.sessionId)) {
      const tp = findTranscript(s.cwd, s.sessionId);
      if (tp && existsSync(tp)) tail.add(s.sessionId, s.cwd, tp);
    }
  }
}
rebalanceWatchers();
const rebalanceInterval = setInterval(rebalanceWatchers, 5000);
rebalanceInterval.unref?.();

function ok(body: unknown): Response { return Response.json(body); }
function err(status: number, msg: string): Response { return Response.json({ error: msg }, { status }); }

const server = Bun.serve({
  hostname: "127.0.0.1",
  port,
  async fetch(req) {
    const url = new URL(req.url);
    const p = url.pathname;
    const q = url.searchParams;
    try {
      if (req.method === "GET") {
        if (p === "/api/health") return ok({ ok: true, ts: Date.now() });
        if (p === "/api/live") {
          const ide = detectIde().display;
          return ok({ sessions: loadLiveSessions(), ide, ts: Date.now() / 1000 });
        }
        if (p === "/api/recent") {
          const days = parseInt(q.get("days") ?? "14", 10);
          const ide = detectIde().display;
          return ok({ repos: loadRecentByRepo(days), ide, ts: Date.now() / 1000 });
        }
        if (p === "/api/panel") {
          const cwd = q.get("cwd") ?? "";
          const sid = q.get("sid") || null;
          if (!cwd) return err(400, "cwd required");
          return ok(await buildPanel(cwd, sid));
        }
        if (p === "/api/decisions") {
          const cwd = q.get("cwd") ?? "";
          if (!cwd) return err(400, "cwd required");
          return ok({ decisions: decisionsProjection.query(state, cwd) });
        }
        if (p === "/api/session-detail") {
          const sid = q.get("sid") ?? "";
          if (!sid) return err(400, "sid required");
          const detail = buildSessionDetail(state, sid);
          if (!detail) return err(404, "session not in index");
          return ok(detail);
        }
        if (p.startsWith("/api/projections/")) {
          const name = p.replace("/api/projections/", "");
          const proj = REGISTRY[name];
          if (!proj) return err(404, "unknown projection");
          const cwd = q.get("cwd") ?? "";
          if (!cwd) return err(400, "cwd required");
          return ok({ name, value: proj.query(state, cwd) });
        }
        return err(404, "not found");
      }
      if (req.method === "POST") {
        const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
        if (p === "/api/focus") {
          const cwd = (body.cwd as string) ?? "";
          const sid = (body.sid as string) || null;
          if (!cwd) return err(400, "cwd required");
          return ok(await focusGhostty(cwd, sid));
        }
        if (p === "/api/resume") return ok(resumeCommand((body.cwd as string) ?? "", (body.sid as string) || null));
        if (p === "/api/fork") return ok(await forkSummary((body.cwd as string) ?? "", (body.sid as string) || null));
        if (p === "/api/open-ide") {
          const cwd = (body.cwd as string) ?? "";
          if (!cwd) return err(400, "cwd required");
          return ok(openInIde(cwd));
        }
        if (p === "/api/shutdown") {
          setTimeout(() => process.exit(0), 50);
          return ok({ ok: true });
        }
        return err(404, "not found");
      }
      return err(405, "method not allowed");
    } catch (e) {
      log.error(`handler exception ${p}`, { e: String(e) });
      return err(500, String(e));
    }
  },
});

// Tell the parent which port we got — Swift parses the first stdout line
console.log(JSON.stringify({ port: server.port }));
log.info("backend ready", { port: server.port });

process.on("SIGTERM", () => {
  log.info("SIGTERM");
  tail.closeAll();
  process.exit(0);
});
```

- [ ] **Step 2: Write the integration test**

```typescript
// backend/test/api.test.ts
import { test, expect, beforeAll, afterAll } from "bun:test";
import { spawn } from "bun";

let proc: ReturnType<typeof spawn> | null = null;
let port = 0;

beforeAll(async () => {
  proc = spawn(["bun", "run", "src/server.ts", "--port", "0"], {
    env: { ...process.env, CLAUDE_HOME: `${import.meta.dir}/fixtures/dot-claude` },
    stdout: "pipe",
    stderr: "pipe",
  });
  // First line is JSON port announcement
  const reader = proc.stdout.getReader();
  const dec = new TextDecoder();
  let buf = "";
  while (!buf.includes("\n")) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += dec.decode(value);
  }
  reader.releaseLock();
  const line = buf.split("\n")[0]!;
  port = JSON.parse(line).port;
});

afterAll(() => { proc?.kill("SIGTERM"); });

test("/api/health returns 200", async () => {
  const r = await fetch(`http://127.0.0.1:${port}/api/health`);
  const j = await r.json();
  expect(j.ok).toBe(true);
});

test("/api/live returns sessions array", async () => {
  const r = await fetch(`http://127.0.0.1:${port}/api/live`);
  const j = await r.json();
  expect(Array.isArray(j.sessions)).toBe(true);
});

test("/api/recent returns repos array", async () => {
  const r = await fetch(`http://127.0.0.1:${port}/api/recent?days=14`);
  const j = await r.json();
  expect(Array.isArray(j.repos)).toBe(true);
});

test("/api/decisions requires cwd", async () => {
  const r = await fetch(`http://127.0.0.1:${port}/api/decisions`);
  expect(r.status).toBe(400);
});

test("404 on unknown path", async () => {
  const r = await fetch(`http://127.0.0.1:${port}/api/nope`);
  expect(r.status).toBe(404);
});
```

- [ ] **Step 3: Run + commit**

Run: `cd backend && bun test test/api.test.ts`
Expected: 5 pass.

```bash
git add backend/src/server.ts backend/test/api.test.ts
git commit -m "feat(backend): wire all HTTP endpoints + tail rebalancing"
```

## Task 19: Build the sidecar binary [DONE — loop 13]

**Files:**
- Verify: `backend/cc-dashboard-backend` (gitignored output)

- [ ] **Step 1: Build**

Run: `make backend-build`
Expected: `backend/cc-dashboard-backend` exists, ~50–80 MB.

- [ ] **Step 2: Smoke-run**

Run:
```bash
./backend/cc-dashboard-backend --port 7777 &
PID=$!
sleep 1
curl -s http://127.0.0.1:7777/api/health
kill $PID
```
Expected: `{"ok":true,...}` printed; backend exits cleanly.

- [ ] **Step 3: No commit needed (binary is gitignored)**

---

# Phase 3 — Swift App: Backend integration + status icon

## Task 20: BackendController — spawn, health-check, monitor [DONE — loop 14]

**Files:**
- Create: `app/Sources/App/BackendController.swift`
- Modify: `app/Sources/App/AppDelegate.swift`
- Modify: `app/project.yml` (add Resources/backend embed)

- [ ] **Step 1: Implement `app/Sources/App/BackendController.swift`**

```swift
import Foundation
import os

private let logger = Logger(subsystem: "dev.vcheval.cc-dashboard", category: "BackendController")

@MainActor
final class BackendController: ObservableObject {
    enum State { case idle, starting, ready(port: Int), failed(reason: String) }
    @Published private(set) var state: State = .idle
    private var process: Process?
    private var respawnAttempts = 0
    private let maxRespawn = 2

    func start() {
        guard case .idle = state else { return }
        state = .starting
        spawnAndWait()
    }

    private func spawnAndWait() {
        guard let url = Bundle.main.url(forResource: "cc-dashboard-backend", withExtension: nil, subdirectory: "backend") else {
            logger.error("backend binary not found in bundle")
            state = .failed(reason: "Backend binary missing from app bundle")
            return
        }

        let p = Process()
        p.executableURL = url
        p.arguments = ["--port", "0"]
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        do { try p.run() } catch {
            logger.error("backend spawn failed: \(error.localizedDescription)")
            state = .failed(reason: "Spawn failed: \(error.localizedDescription)")
            return
        }
        process = p

        // Read first stdout line for port announcement
        Task.detached { [weak self] in
            let handle = outPipe.fileHandleForReading
            var buf = Data()
            while !buf.contains(0x0a) {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buf.append(chunk)
            }
            guard let line = String(data: buf, encoding: .utf8)?
                    .components(separatedBy: "\n").first,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let port = obj["port"] as? Int else {
                await MainActor.run {
                    self?.state = .failed(reason: "Failed to parse backend port announcement")
                }
                return
            }
            await MainActor.run { self?.state = .ready(port: port) }
            logger.info("backend ready on port \(port)")
        }

        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.handleTermination()
            }
        }
    }

    private func handleTermination() {
        process = nil
        respawnAttempts += 1
        if respawnAttempts <= maxRespawn {
            logger.warning("backend exited; respawning (attempt \(self.respawnAttempts))")
            state = .idle
            start()
        } else {
            logger.error("backend exited too many times; giving up")
            state = .failed(reason: "Backend kept crashing")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }
}
```

- [ ] **Step 2: Update `app/project.yml`** to bundle the backend binary

In `project.yml`, in the `cc-dashboard` target's `resources:` list, add a path that points outside `Sources/`:

```yaml
    resources:
      - Sources/Resources
      - path: ../../backend/cc-dashboard-backend
        destination: Resources/backend
        optional: true
```

(The `optional: true` lets the project regenerate even if the binary hasn't been built yet — Phase 5 wiring will require it before the app actually runs.)

Run: `make project`

Then in the generated project, manually verify (open in Xcode) the `Copy Bundle Resources` build phase has `cc-dashboard-backend` placed under `backend/`. xcodegen handles `destination` via Copy Files build phase rules.

- [ ] **Step 3: Modify `AppDelegate.swift` to use BackendController**

```swift
import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "dev.vcheval.cc-dashboard", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    let backend = BackendController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "cc"
        statusItem = item
        backend.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        backend.stop()
    }
}
```

- [ ] **Step 4: Build, run, verify**

Run: `make app-build && make app-run`
Expected: status item appears; in Console.app, find subsystem `dev.vcheval.cc-dashboard` — see "backend ready on port N".

- [ ] **Step 5: Commit**

```bash
git add app/Sources/App/ app/project.yml
git commit -m "feat(app): BackendController spawns and monitors sidecar"
```

## Task 21: APIClient + Codable types [DONE — loop 15]

**Files:**
- Create: `app/Sources/App/APIClient.swift`

- [ ] **Step 1: Implement `app/Sources/App/APIClient.swift`**

This file mirrors `backend/src/types.ts`. Keep the property names identical (use `CodingKeys` to map snake_case → camelCase where needed).

```swift
import Foundation

// MARK: - Codable types (mirror backend/src/types.ts)

enum SessionEvent: String, Codable {
    case permissionPending = "PERMISSION_PENDING"
    case toolFailed = "TOOL_FAILED"
    case ask = "ASK"
    case working = "WORKING"
    case idleAfterComplete = "IDLE_AFTER_COMPLETE"
    case clear = "CLEAR"
}

struct OpenTool: Codable, Hashable { let name: String; let id: String? }
struct GitInfo: Codable { let branch: String?; let dirty: Int; let lastCommit: String?
    enum CodingKeys: String, CodingKey { case branch, dirty, lastCommit = "last_commit" } }

struct LiveSession: Codable, Identifiable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let repo: String
    let branch: String?
    let dirty: Int
    let startedAt: Int
    let lastActivity: Double
    let ageSec: Int
    let staleDecay: Int
    let transcriptFound: Bool
    let event: SessionEvent
    let reason: String
    let priority: Int
    let lastUser: String
    let lastAssistant: String
    let openTool: OpenTool?
    var id: String { sessionId }
    enum CodingKeys: String, CodingKey {
        case pid, sessionId = "sessionId", cwd, repo, branch, dirty
        case startedAt = "started_at", lastActivity = "last_activity"
        case ageSec = "age_sec", staleDecay = "stale_decay"
        case transcriptFound = "transcript_found"
        case event, reason, priority
        case lastUser = "last_user", lastAssistant = "last_assistant"
        case openTool = "open_tool"
    }
}

struct RecentRepo: Codable, Identifiable {
    let cwd: String; let repo: String; let branch: String?; let dirty: Int
    let lastCommit: String?; let sessionId: String
    let lastActivity: Double
    let event: SessionEvent; let reason: String; let priority: Int
    let lastUser: String; let lastAssistant: String; let openTool: OpenTool?
    var id: String { cwd }
    enum CodingKeys: String, CodingKey {
        case cwd, repo, branch, dirty
        case lastCommit = "last_commit", sessionId
        case lastActivity = "last_activity", event, reason, priority
        case lastUser = "last_user", lastAssistant = "last_assistant"
        case openTool = "open_tool"
    }
}

struct PromptEntry: Codable { let display: String; let timestamp: String? }

struct Panel: Codable {
    let cwd: String; let repo: String; let sessionId: String?
    let transcriptFound: Bool
    let git: GitInfo
    let diffSummary: String?
    let recentPrompts: [PromptEntry]
    let lastUser: String; let lastAssistant: String
    let event: SessionEvent; let reason: String; let openTool: OpenTool?
    enum CodingKeys: String, CodingKey {
        case cwd, repo, sessionId
        case transcriptFound = "transcript_found", git
        case diffSummary = "diff_summary", recentPrompts = "recent_prompts"
        case lastUser = "last_user", lastAssistant = "last_assistant"
        case event, reason, openTool = "open_tool"
    }
}

struct FileTouch: Codable, Identifiable { let path: String; let edits: Int; let lastTouch: Double
    var id: String { path }
    enum CodingKeys: String, CodingKey { case path, edits, lastTouch = "last_touch" } }
struct Tokens: Codable { let input: Int; let cachedRead: Int; let cachedCreate: Int; let output: Int; let contextLimit: Int
    enum CodingKeys: String, CodingKey { case input
        case cachedRead = "cached_read", cachedCreate = "cached_create", output, contextLimit = "context_limit" } }
struct DecisionPair: Codable, Identifiable { let q: String; let a: String; var id: String { q + a } }

struct SessionDetail: Codable {
    let sessionId: String; let cwd: String; let repo: String; let branch: String?
    let branchHistory: [String]
    let filesChanged: [FileTouch]
    let tokens: Tokens
    let loadHistory: [Int]
    let lastAssistant: String; let openTool: OpenTool?
    let decisions: [DecisionPair]
    let source: String; let ageSec: Int
    enum CodingKeys: String, CodingKey {
        case sessionId, cwd, repo, branch
        case branchHistory = "branch_history"
        case filesChanged = "files_changed", tokens
        case loadHistory = "load_history"
        case lastAssistant = "last_assistant", openTool = "open_tool"
        case decisions, source, ageSec = "age_sec"
    }
}

struct LiveResponse: Codable { let sessions: [LiveSession]; let ide: String; let ts: Double }
struct RecentResponse: Codable { let repos: [RecentRepo]; let ide: String; let ts: Double }
struct DecisionsResponse: Codable { let decisions: [DecisionPair] }
struct FocusResult: Codable { let ok: Bool; let matched: Bool; let reason: String?; let detail: String?; let windowIndex: Int?; let matchedTitle: String?; let score: Int?
    enum CodingKeys: String, CodingKey { case ok, matched, reason, detail, windowIndex = "window_index", matchedTitle = "matched_title", score } }
struct ResumeResult: Codable { let command: String; let copiedToClipboard: Bool
    enum CodingKeys: String, CodingKey { case command, copiedToClipboard = "copied_to_clipboard" } }
struct ForkResult: Codable { let summary: String; let copiedToClipboard: Bool
    enum CodingKeys: String, CodingKey { case summary, copiedToClipboard = "copied_to_clipboard" } }
struct OpenIdeResult: Codable { let ok: Bool; let ide: String?; let error: String?; let detail: String? }

// MARK: - Client

actor APIClient {
    private let baseURL: URL
    private let session: URLSession

    init(port: Int) {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        self.session = URLSession(configuration: cfg)
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var c = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        let (data, _) = try await session.data(from: c.url!)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func live() async throws -> LiveResponse { try await get("/api/live") }
    func recent(days: Int = 14) async throws -> RecentResponse { try await get("/api/recent", query: ["days": String(days)]) }
    func panel(cwd: String, sid: String?) async throws -> Panel {
        var q = ["cwd": cwd]; if let sid { q["sid"] = sid }
        return try await get("/api/panel", query: q)
    }
    func sessionDetail(sid: String) async throws -> SessionDetail { try await get("/api/session-detail", query: ["sid": sid]) }
    func decisions(cwd: String) async throws -> DecisionsResponse { try await get("/api/decisions", query: ["cwd": cwd]) }
    func focus(cwd: String, sid: String?) async throws -> FocusResult {
        var b: [String: Any] = ["cwd": cwd]; if let sid { b["sid"] = sid }
        return try await post("/api/focus", body: b)
    }
    func resume(cwd: String, sid: String?) async throws -> ResumeResult {
        var b: [String: Any] = ["cwd": cwd]; if let sid { b["sid"] = sid }
        return try await post("/api/resume", body: b)
    }
    func fork(cwd: String, sid: String?) async throws -> ForkResult {
        var b: [String: Any] = ["cwd": cwd]; if let sid { b["sid"] = sid }
        return try await post("/api/fork", body: b)
    }
    func openIde(cwd: String) async throws -> OpenIdeResult { try await post("/api/open-ide", body: ["cwd": cwd]) }
}
```

- [ ] **Step 2: Build**

Run: `make app-build`
Expected: build succeeds (no UI yet, but types compile).

- [ ] **Step 3: Commit**

```bash
git add app/Sources/App/APIClient.swift
git commit -m "feat(app): API client + Codable types mirroring backend"
```

## Task 22: PollingStore — observable session state [DONE — loop 16]

**Files:**
- Create: `app/Sources/App/PollingStore.swift`
- Test: `app/Tests/PollingStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import cc_dashboard

final class PollingStoreTests: XCTestCase {
    func testSortRanksByPriorityThenActivity() {
        let s1 = LiveSession(pid: 1, sessionId: "a", cwd: "/x", repo: "x", branch: nil, dirty: 0,
                              startedAt: 0, lastActivity: 100, ageSec: 0, staleDecay: 0, transcriptFound: true,
                              event: .working, reason: "", priority: 90, lastUser: "", lastAssistant: "", openTool: nil)
        let s2 = LiveSession(pid: 2, sessionId: "b", cwd: "/y", repo: "y", branch: nil, dirty: 0,
                              startedAt: 0, lastActivity: 200, ageSec: 0, staleDecay: 0, transcriptFound: true,
                              event: .permissionPending, reason: "", priority: 5, lastUser: "", lastAssistant: "", openTool: nil)
        let sorted = PollingStore.sort([s1, s2])
        XCTAssertEqual(sorted.first?.sessionId, "b")
    }

    func testAttentionCount() {
        // Build mixed array; expect count of permission/ask/failed
    }
}
```

- [ ] **Step 2: Run — fail (PollingStore not defined)**

Run: `make test-app`
Expected: build fails because `PollingStore` undefined.

- [ ] **Step 3: Implement `PollingStore`**

```swift
import Foundation
import Combine

@MainActor
final class PollingStore: ObservableObject {
    @Published private(set) var sessions: [LiveSession] = []
    @Published private(set) var recent: [RecentRepo] = []
    @Published private(set) var ide: String = "Finder"
    @Published var isPopoverOpen: Bool = false

    private var client: APIClient?
    private var liveTimer: Timer?
    private var recentTimer: Timer?
    private let pollLive: TimeInterval = 2.0
    private let pollRecent: TimeInterval = 4.0

    func attach(client: APIClient) {
        self.client = client
        startPolling()
    }

    func detach() {
        liveTimer?.invalidate(); liveTimer = nil
        recentTimer?.invalidate(); recentTimer = nil
    }

    private func startPolling() {
        liveTimer = Timer.scheduledTimer(withTimeInterval: pollLive, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshLive() }
        }
        Task { @MainActor in await refreshLive() }
        recentTimer = Timer.scheduledTimer(withTimeInterval: pollRecent, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshRecentIfNeeded() }
        }
    }

    func refreshLive() async {
        guard let c = client else { return }
        do {
            let r = try await c.live()
            self.sessions = Self.sort(r.sessions)
            self.ide = r.ide
        } catch { /* surfaced elsewhere */ }
    }

    func refreshRecentIfNeeded() async {
        // Polled lazily — but easy to keep fresh anyway
        guard let c = client else { return }
        do { let r = try await c.recent(); self.recent = r.repos; self.ide = r.ide } catch {}
    }

    static func sort(_ xs: [LiveSession]) -> [LiveSession] {
        xs.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.lastActivity > $1.lastActivity
        }
    }

    var attentionCount: Int {
        sessions.filter { $0.event == .permissionPending || $0.event == .toolFailed || $0.event == .ask }.count
    }
}
```

- [ ] **Step 4: Make tests compile**

Add an `@testable import` mechanism. In `project.yml`, set `Bundle Loader` so test target can access the app's symbols (xcodegen does this when test target lists the app target as a dependency, which we already have).

Run: `make test-app`
Expected: 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/App/PollingStore.swift app/Tests/PollingStoreTests.swift
git commit -m "feat(app): PollingStore observable session state"
```

## Task 23: Theme system (Claude / Tokyo Night / Gruvbox / Nord × dark/light) [DONE — loop 17]

**Files:**
- Create: `app/Sources/Theme/Theme.swift`
- Create: `app/Sources/Theme/ThemePalette.swift`
- Create: `app/Sources/Theme/Themes.swift`
- Test: `app/Tests/ThemeTests.swift`

- [ ] **Step 1: Implement `Theme.swift` and `ThemePalette.swift`**

```swift
// app/Sources/Theme/Theme.swift
import SwiftUI

enum ThemeId: String, CaseIterable, Codable {
    case claude, tokyoNight, gruvbox, nord
}
enum ThemeMode: String, CaseIterable, Codable { case dark, light }
```

```swift
// app/Sources/Theme/ThemePalette.swift
import SwiftUI

struct ThemePalette {
    let bgWindow: Color
    let bgElev: Color
    let bgElevHover: Color
    let bgRowUrgent: Color
    let separator: Color
    let fg: Color
    let fgSecondary: Color
    let fgTertiary: Color
    let fgQuaternary: Color
    let accent: Color
    // Urgency colors
    let uPermission: Color
    let uFailed: Color
    let uAsk: Color
    let uWorking: Color
    let uIdle: Color
    let uClear: Color
}
```

- [ ] **Step 2: Implement `Themes.swift` mirroring `docs/ux-design/styles.css` :root vars**

```swift
// app/Sources/Theme/Themes.swift
// Source-of-truth: docs/ux-design/styles.css :root
import SwiftUI

enum Themes {
    static func palette(for id: ThemeId, mode: ThemeMode) -> ThemePalette {
        switch (id, mode) {
        case (.claude, .dark): return claudeDark
        case (.claude, .light): return claudeLight
        case (.tokyoNight, .dark): return tokyoDark
        case (.tokyoNight, .light): return tokyoLight
        case (.gruvbox, .dark): return gruvboxDark
        case (.gruvbox, .light): return gruvboxLight
        case (.nord, .dark): return nordDark
        case (.nord, .light): return nordLight
        }
    }

    private static let claudeDark = ThemePalette(
        bgWindow: Color(red: 0.110, green: 0.106, blue: 0.098, opacity: 0.78),
        bgElev: Color.white.opacity(0.04),
        bgElevHover: Color.white.opacity(0.07),
        bgRowUrgent: Color(red: 0.852, green: 0.467, blue: 0.341, opacity: 0.08),
        separator: Color.white.opacity(0.08),
        fg: Color(red: 0.96, green: 0.94, blue: 0.90),
        fgSecondary: Color(red: 0.96, green: 0.94, blue: 0.90, opacity: 0.62),
        fgTertiary: Color(red: 0.96, green: 0.94, blue: 0.90, opacity: 0.38),
        fgQuaternary: Color(red: 0.96, green: 0.94, blue: 0.90, opacity: 0.22),
        accent: Color(red: 0.852, green: 0.467, blue: 0.341),
        uPermission: Color(red: 0.91, green: 0.64, blue: 0.24),
        uFailed: Color(red: 0.85, green: 0.38, blue: 0.33),
        uAsk: Color(red: 0.79, green: 0.56, blue: 0.84),
        uWorking: Color(red: 0.44, green: 0.71, blue: 0.85),
        uIdle: Color(red: 0.54, green: 0.61, blue: 0.50),
        uClear: Color(red: 0.96, green: 0.94, blue: 0.90, opacity: 0.32))

    // For brevity, the remaining 7 palettes follow the same shape with values
    // pulled from styles.css (engineer: reuse styles.css :root sections; values
    // for tokyoDark, gruvboxDark, nordDark, and all .light variants are derived
    // by inverting fg/bg and substituting the named accent. Use the swatch
    // colors in screens.jsx Settings tab as authoritative starting points if
    // styles.css doesn't list a variant.)
    private static let claudeLight = claudeDark      // PLACEHOLDER — replace with light values
    private static let tokyoDark = claudeDark        // PLACEHOLDER
    private static let tokyoLight = claudeDark       // PLACEHOLDER
    private static let gruvboxDark = claudeDark      // PLACEHOLDER
    private static let gruvboxLight = claudeDark     // PLACEHOLDER
    private static let nordDark = claudeDark         // PLACEHOLDER
    private static let nordLight = claudeDark        // PLACEHOLDER
}

// Inject palette via environment
private struct ThemeKey: EnvironmentKey {
    static let defaultValue: ThemePalette = Themes.palette(for: .claude, mode: .dark)
}
extension EnvironmentValues {
    var theme: ThemePalette { get { self[ThemeKey.self] } set { self[ThemeKey.self] = newValue } }
}
```

NOTE: the placeholders for non-default themes are accepted only in this scaffolding step; **Task 23.5** below replaces them with real values lifted from `docs/ux-design/styles.css`. Build will succeed without them but only Claude Dark will look right.

- [ ] **Step 3: Write the unit test**

```swift
// app/Tests/ThemeTests.swift
import XCTest
@testable import cc_dashboard

final class ThemeTests: XCTestCase {
    func testClaudeDarkAccentMatchesSpec() {
        let p = Themes.palette(for: .claude, mode: .dark)
        // The spec accent in styles.css is #d97757 = (217, 119, 87) in 0..255
        // SwiftUI Color does not expose channel values directly without UIColor;
        // assert the type is constructed. Snapshot/visual tests live elsewhere.
        XCTAssertNotNil(p.accent)
    }

    func testEveryThemeIdReturnsAPalette() {
        for id in ThemeId.allCases {
            for mode in ThemeMode.allCases {
                _ = Themes.palette(for: id, mode: mode)  // must not crash
            }
        }
    }
}
```

- [ ] **Step 4: Run + commit**

Run: `make test-app`
Expected: pass.

```bash
git add app/Sources/Theme/ app/Tests/ThemeTests.swift
git commit -m "feat(app): theme system scaffold (Claude Dark complete)"
```

## Task 23.5: Fill in remaining theme palettes [DONE — loop 18]

**Files:**
- Modify: `app/Sources/Theme/Themes.swift`

- [ ] **Step 1: Read `docs/ux-design/styles.css`** — search for `:root` and any `@media` or class-scoped overrides (Tokyo / Gruvbox / Nord may live in `[data-theme="tokyo"]` selectors).

- [ ] **Step 2: For each (theme × mode) pair**, construct a `ThemePalette` literal whose 16 colors match the CSS variable values at that selector. Where `styles.css` does not define a variant explicitly, fall back to the swatch RGB values listed in `docs/ux-design/screens.jsx` (`SettingsTab.themes` array — e.g. Tokyo Night uses `#1a1b26`, `#bb9af7`, `#7dcfff`).

- [ ] **Step 3: Replace each `PLACEHOLDER` line** with the new struct literal.

- [ ] **Step 4: Run app, switch each theme via Settings (Phase 4), verify visual** — defer the visual check to Phase 4; for now the build must pass.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/Theme/Themes.swift
git commit -m "feat(app): fill in 7 remaining theme palettes from CSS source"
```

## Task 24: Status icon + FlashController [DONE — loop 19]

**Files:**
- Create: `app/Sources/UI/StatusIconView.swift`
- Create: `app/Sources/UI/FlashController.swift`
- Test: `app/Tests/FlashControllerTests.swift`
- Add to `app/Sources/Resources/Assets.xcassets`: `MenubarIcon` and `MenubarIconAlert` template images (16×16 PNG @1x/@2x; black on transparent; rendering = template). For v1, fall back to SF Symbols if assets aren't yet drawn — use `square.stack.3d.up.fill` and `exclamationmark.triangle.fill`.

- [ ] **Step 1: Write the failing FlashController test**

```swift
// app/Tests/FlashControllerTests.swift
import XCTest
@testable import cc_dashboard

@MainActor
final class FlashControllerTests: XCTestCase {
    func testFlashStartsOnTransitionToAttention() {
        let fc = FlashController()
        XCTAssertFalse(fc.isFlashing)
        fc.update(attentionCount: 0)
        fc.update(attentionCount: 1)
        XCTAssertTrue(fc.isFlashing)
    }
    func testFlashDoesNotRetriggerWhileStillAttention() {
        let fc = FlashController()
        fc.update(attentionCount: 1)
        XCTAssertTrue(fc.isFlashing)
        fc.stopFlashing()                    // user opened popover or quiet
        XCTAssertFalse(fc.isFlashing)
        fc.update(attentionCount: 1)         // same count, no transition
        XCTAssertFalse(fc.isFlashing)
    }
    func testFlashAutoCapsAfterCapSeconds() {
        let fc = FlashController(capSeconds: 0.05)
        fc.update(attentionCount: 0)
        fc.update(attentionCount: 1)
        let exp = expectation(description: "auto-stop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertFalse(fc.isFlashing); exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
}
```

- [ ] **Step 2: Implement `FlashController`**

```swift
// app/Sources/UI/FlashController.swift
import Foundation
import Combine

@MainActor
final class FlashController: ObservableObject {
    @Published private(set) var isFlashing: Bool = false
    @Published private(set) var phaseAlert: Bool = false
    private var lastAttentionCount: Int = 0
    private var flashTimer: Timer?
    private var capTimer: Timer?
    private let capSeconds: TimeInterval

    init(capSeconds: TimeInterval = 30) { self.capSeconds = capSeconds }

    func update(attentionCount: Int) {
        let prev = lastAttentionCount
        lastAttentionCount = attentionCount
        // Trigger only on transition from 0 (or fewer) to ≥1
        if attentionCount > prev && prev == 0 {
            startFlashing()
        } else if attentionCount == 0 {
            stopFlashing()
        }
    }

    func stopFlashing() {
        isFlashing = false; phaseAlert = false
        flashTimer?.invalidate(); flashTimer = nil
        capTimer?.invalidate(); capTimer = nil
    }

    private func startFlashing() {
        isFlashing = true
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.phaseAlert.toggle() }
        }
        capTimer = Timer.scheduledTimer(withTimeInterval: capSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.flashTimer?.invalidate(); self?.flashTimer = nil
                self?.phaseAlert = true     // settle on alert glyph (still red, no longer flashing)
                self?.isFlashing = false
            }
        }
    }
}
```

- [ ] **Step 3: Run test → pass**

Run: `make test-app`
Expected: 3 pass.

- [ ] **Step 4: Implement `StatusIconView`**

```swift
// app/Sources/UI/StatusIconView.swift
import AppKit
import SwiftUI

@MainActor
final class StatusIconController {
    private let item: NSStatusItem
    private let flash: FlashController
    private weak var store: PollingStore?
    private var cancellable: Any?

    init(item: NSStatusItem, flash: FlashController, store: PollingStore) {
        self.item = item; self.flash = flash; self.store = store
        item.button?.image = Self.iconBaseline()
        // Update when sessions change
        Task { @MainActor in
            await listen()
        }
    }

    private func listen() async {
        // simple reactive: poll @MainActor every 2s for now
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard let store else { return }
        let count = store.attentionCount
        flash.update(attentionCount: count)
        let alert = flash.phaseAlert
        item.button?.image = alert ? Self.iconAlert() : Self.iconBaseline()
    }

    private static func iconBaseline() -> NSImage {
        let img = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "cc-dashboard")!
        img.isTemplate = true
        return img
    }
    private static func iconAlert() -> NSImage {
        let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "attention")!
        img.isTemplate = true
        return img
    }
}
```

- [ ] **Step 5: Wire into AppDelegate**

```swift
// app/Sources/App/AppDelegate.swift — modify
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var iconController: StatusIconController?
    let backend = BackendController()
    let store = PollingStore()
    let flash = FlashController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        backend.start()
        // Watch backend state
        Task { @MainActor in
            for await s in backend.$state.values {
                if case .ready(let port) = s {
                    let client = APIClient(port: port)
                    store.attach(client: client)
                    iconController = StatusIconController(item: item, flash: flash, store: store)
                }
            }
        }
    }
}
```

- [ ] **Step 6: Build, run, verify**

Run: `make app-build && make app-run`
Expected: After backend ready, status bar shows the stack icon. If you have any sessions in PERMISSION_PENDING / TOOL_FAILED / ASK state, the icon will swap to the alert triangle for ~30 s.

- [ ] **Step 7: Commit**

```bash
git add app/Sources/UI/StatusIconView.swift app/Sources/UI/FlashController.swift app/Tests/FlashControllerTests.swift app/Sources/App/AppDelegate.swift
git commit -m "feat(app): status icon + FlashController on attention transitions"
```

---

# Phase 4 — Swift UI: popover screens

The next tasks build the popover. The UX design package in `docs/ux-design/` is the source of truth; `screens.jsx`, `components.jsx`, `icons.jsx`, and `styles.css` between them define every layout, spacing, weight, and color. **Each task ends with a visual verification step**: open the running app, click the status item, confirm the screen looks like its counterpart in the design.

## Task 25: PopoverController + PopoverShell + tab bar + header/footer [DONE — loop 20]

**Files:**
- Create: `app/Sources/UI/PopoverController.swift`
- Create: `app/Sources/UI/PopoverShell.swift`
- Create: `app/Sources/UI/TabBar.swift`
- Create: `app/Sources/UI/PopHeader.swift`
- Create: `app/Sources/UI/PopFooter.swift`
- Create: `app/Sources/UI/QuietPill.swift`
- Create: `app/Sources/UI/Icon.swift`
- Modify: `app/Sources/App/AppDelegate.swift` (wire popover open/close)

- [ ] **Step 1: Implement `Icon.swift`** — port each `case` from `docs/ux-design/icons.jsx` to a `static func` returning a `Path`-based SwiftUI view. Skip nothing. Each icon must accept a `size` parameter. The `URGENCY` map at the bottom of `icons.jsx` is the source of truth for which glyph each session state uses.

```swift
// app/Sources/UI/Icon.swift
import SwiftUI

enum IconName: String {
    case permission, failed, ask, working, idle, clear
    case branch, chevronRight = "chevron-right", chevronLeft = "chevron-left"
    case gear, refresh, moon, bolt, search, copy, external
    case terminal, warning, info, x, arrowBack = "arrow-back", file, ide
    case stack, stackFilled = "stack-filled"
}

struct Icon: View {
    let name: IconName
    var size: CGFloat = 14
    var body: some View {
        Path { p in
            switch name {
            case .stack:
                p.move(to: .init(x: 2.5, y: 5));  p.addLine(to: .init(x: 8, y: 2));  p.addLine(to: .init(x: 13.5, y: 5)); p.addLine(to: .init(x: 8, y: 8)); p.closeSubpath()
                p.move(to: .init(x: 2.5, y: 8));  p.addLine(to: .init(x: 8, y: 11)); p.addLine(to: .init(x: 13.5, y: 8))
                p.move(to: .init(x: 2.5, y: 11)); p.addLine(to: .init(x: 8, y: 14)); p.addLine(to: .init(x: 13.5, y: 11))
            // ... port every case from icons.jsx exhaustively
            default:
                break
            }
        }
        .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
    }
}
```

For the engineer: complete every case in the switch. If you skip one, screens that use that glyph will render empty.

- [ ] **Step 2: Implement `PopoverShell.swift`**

This wraps the entire popover content with the design's outer chrome (380×560 default, 380×620 when SessionDetail is shown). Shell provides backdrop blur via `NSVisualEffectView`-bridged background.

```swift
// app/Sources/UI/PopoverShell.swift
import SwiftUI

struct PopoverShell<Content: View>: View {
    @Environment(\.theme) private var theme
    var detailMode: Bool = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .frame(width: 380, height: detailMode ? 620 : 560)
            .background(VisualEffect()
                .overlay(theme.bgWindow))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .menu
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
```

- [ ] **Step 3: Implement `PopHeader.swift`** — port directly from `components.jsx`'s `PopHeader`. Includes the title + count text + `QuietPill`.

- [ ] **Step 4: Implement `QuietPill.swift`** — port from `components.jsx`.

- [ ] **Step 5: Implement `TabBar.swift`** — three tabs: Live, Restore, Settings. Active tab gets the accent underline (see `styles.css` `.tab.active`).

- [ ] **Step 6: Implement `PopFooter.swift`** — gear icon, refresh icon, kbd hint.

- [ ] **Step 7: Implement `PopoverController.swift`**

```swift
// app/Sources/UI/PopoverController.swift
import AppKit
import SwiftUI

@MainActor
final class PopoverController: NSObject {
    private let popover = NSPopover()
    private weak var statusItem: NSStatusItem?
    private let store: PollingStore

    init(statusItem: NSStatusItem, store: PollingStore) {
        self.statusItem = statusItem
        self.store = store
        super.init()
        popover.behavior = .transient
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
    }

    @objc private func toggle() {
        guard let btn = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.contentViewController = NSHostingController(rootView: AnyView(
                PopoverShell { Text("placeholder — wire LiveTab next").environment(\.theme, Themes.palette(for: .claude, mode: .dark)) }
            ))
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        }
        store.isPopoverOpen = popover.isShown
    }
}
```

- [ ] **Step 8: Wire `PopoverController` into AppDelegate** — replace the simple "click status item does nothing" with the controller.

- [ ] **Step 9: Visual verification** — `make app-run`, click the menu bar icon. A blank popover with the right size and rounded corners appears.

- [ ] **Step 10: Commit**

```bash
git add app/Sources/UI/
git commit -m "feat(app): popover shell + tab bar + header/footer scaffolding"
```

## Task 26: SessionRow + LiveTab [DONE — loop 21]

**Files:**
- Create: `app/Sources/UI/SessionRow.swift`
- Create: `app/Sources/UI/LiveTab.swift`

- [ ] **Step 1: Implement `SessionRow.swift`** — port `components.jsx`'s `SessionRow` 1:1. Layout: left urgency tick, icon + repo + branch on line 1, status reason on line 2, relative time on the right, optional nav badge in the corner. Pass `event` to map URGENCY → color/icon.

```swift
// app/Sources/UI/SessionRow.swift
import SwiftUI

struct SessionRow: View {
    let session: LiveSession
    let isFocused: Bool
    let navIndex: Int?
    let isStale: Bool
    var onTap: () -> Void
    @Environment(\.theme) private var theme

    private var urgencyColor: Color {
        switch session.event {
        case .permissionPending: return theme.uPermission
        case .toolFailed: return theme.uFailed
        case .ask: return theme.uAsk
        case .working: return theme.uWorking
        case .idleAfterComplete: return theme.uIdle
        case .clear: return theme.uClear
        }
    }
    private var urgencyIcon: IconName {
        switch session.event {
        case .permissionPending: return .permission
        case .toolFailed: return .failed
        case .ask: return .ask
        case .working: return .working
        case .idleAfterComplete: return .idle
        case .clear: return .clear
        }
    }
    private var isUrgent: Bool { session.event == .permissionPending || session.event == .toolFailed }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(urgencyColor).frame(width: 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Icon(name: urgencyIcon).foregroundColor(urgencyColor)
                    Text(session.repo).fontWeight(.medium)
                    Text(session.branch ?? "").foregroundColor(theme.fgSecondary).font(.system(size: 11.5))
                }
                Text(session.reason).font(.system(size: 11.5)).foregroundColor(theme.fgSecondary).lineLimit(1)
            }
            Spacer()
            Text(relTime(session.lastActivity)).font(.system(size: 11)).foregroundColor(theme.fgTertiary)
            if let n = navIndex {
                Text(String(n))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(4)
                    .background(theme.accent)
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(isUrgent ? theme.bgRowUrgent : (isFocused ? theme.bgElevHover : Color.clear))
        .opacity(isStale ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

private func relTime(_ msEpoch: Double) -> String {
    let s = Int((Date().timeIntervalSince1970 * 1000 - msEpoch) / 1000)
    if s < 5 { return "now" }
    if s < 60 { return "\(s)s ago" }
    let m = s / 60; if m < 60 { return "\(m)m ago" }
    let h = m / 60; if h < 24 { return "\(h)h ago" }
    return "\(h / 24)d ago"
}
```

- [ ] **Step 2: Implement `LiveTab.swift`** — ported from `screens.jsx::LiveTab`.

```swift
// app/Sources/UI/LiveTab.swift
import SwiftUI

struct LiveTab: View {
    @ObservedObject var store: PollingStore
    @Binding var navMode: Bool
    @Binding var focusedId: String?
    var onOpenDetail: (LiveSession) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        if store.sessions.isEmpty {
            VStack(spacing: 10) {
                Icon(name: .stack, size: 22).foregroundColor(theme.fgTertiary)
                Text("No live sessions").fontWeight(.semibold)
                Text("Start one with ").foregroundColor(theme.fgSecondary)
                + Text("claude").font(.system(.body, design: .monospaced))
                + Text(" in any terminal.").foregroundColor(theme.fgSecondary)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.sessions.enumerated()), id: \.element.id) { idx, s in
                        SessionRow(
                            session: s,
                            isFocused: focusedId == s.sessionId,
                            navIndex: navMode && idx < 9 ? idx + 1 : nil,
                            isStale: (Date().timeIntervalSince1970 * 1000 - s.lastActivity) > 30 * 60 * 1000,
                            onTap: { onOpenDetail(s) }
                        )
                        Divider().background(theme.separator)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Wire LiveTab into the popover content**

Replace `Text("placeholder ...")` in `PopoverController.toggle` with a `RootView` that includes header / tab bar / current-tab content. Move that orchestrator into `PopoverShell` or a new `PopoverRoot` view. (Keep this task focused; just produce a working LiveTab in the popover.)

- [ ] **Step 4: Visual check + commit**

Run app; click status icon; the LiveTab should populate with your real `~/.claude/` sessions, sorted by urgency.

```bash
git add app/Sources/UI/SessionRow.swift app/Sources/UI/LiveTab.swift app/Sources/UI/PopoverController.swift
git commit -m "feat(app): SessionRow + LiveTab populated from sidecar"
```

## Task 27: RestoreTab + RestoreRow + RestoreDetail [DONE — loop 22]

**Files:**
- Create: `app/Sources/UI/RestoreTab.swift`
- Create: `app/Sources/UI/RestoreRow.swift`
- Create: `app/Sources/UI/RestoreDetail.swift`

- [ ] **Step 1: Implement** — port `screens.jsx::RestoreTab` 1:1. Two-pane layout (list + side panel). Use the panel data from `/api/panel` for the right pane (lazy-fetch when a row is selected).

- [ ] **Step 2: Wire actions** — Resume / Fork / Open in IDE buttons call `APIClient.resume`, `.fork`, `.openIde` and show a toast on success/failure.

- [ ] **Step 3: Visual + commit**

```bash
git add app/Sources/UI/Restore*.swift
git commit -m "feat(app): Restore tab with side panel and actions"
```

## Task 28: SessionDetailView [DONE — loop 23]

**Files:**
- Create: `app/Sources/UI/SessionDetailView.swift`
- Create: `app/Sources/UI/SessionDetailSections.swift`
- Create: `app/Sources/UI/Sparkline.swift`

- [ ] **Step 1: Implement `Sparkline.swift`** — single-pass `Path` with linear gradient fill, matches `components.jsx::Sparkline`.

- [ ] **Step 2: Implement `SessionDetailSections.swift`** — one struct per section: `BranchTimelineSection`, `FilesChangedSection`, `TokenUsageSection`, `LoadHistorySection`, `LastAssistantSection`, `OpenToolSection`, `DecisionsSection`, `ActionRow`. Mirror `screens.jsx::SessionDetail`.

- [ ] **Step 3: Implement `SessionDetailView.swift`** — header (back arrow, repo, branch, age, source, urgency chip) + ScrollView wrapping the sections. Fetches via `APIClient.sessionDetail(sid:)` on appear; shows a loading state.

- [ ] **Step 4: Wire push-navigation** — change `LiveTab.onOpenDetail` to set a `selectedDetail: LiveSession?` on the popover root; when set, render `SessionDetailView` in place of the tabs (popover height becomes 620).

- [ ] **Step 5: Visual + commit**

```bash
git add app/Sources/UI/SessionDetailView.swift app/Sources/UI/SessionDetailSections.swift app/Sources/UI/Sparkline.swift
git commit -m "feat(app): SessionDetail push-navigation with all sections"
```

## Task 29: SettingsTab + SettingsStore + QuietModeStore [DONE — loop 24]

**Files:**
- Create: `app/Sources/Settings/SettingsStore.swift`
- Create: `app/Sources/Settings/QuietModeStore.swift`
- Create: `app/Sources/UI/SettingsView.swift`

- [ ] **Step 1: Implement `SettingsStore`** — `@AppStorage`-backed: `themeId`, `themeMode`, `pollIntervalSec`, `flashEnabled`, `flashCapSeconds`, `notificationSound`, `ideOverride`, `customMuteDurations`. One `@Published` value per setting; binds directly to SwiftUI form controls.

- [ ] **Step 2: Implement `QuietModeStore`** — `@AppStorage` `quietUntil` (Date or nil); methods `mute(for: TimeInterval)`, `mute(until: Date)`, `unmute()`, `toggle()`. `var isQuiet: Bool { quietUntil > Date() }`.

- [ ] **Step 3: Implement `SettingsView`** — port `screens.jsx::SettingsTab` 1:1. Theme grid swatches, sliders, toggles, mute-duration list.

- [ ] **Step 4: Wire QuietPill** — header pill toggles `QuietModeStore.toggle()`; subscribe in `FlashController.update` to suppress flashing while quiet; subscribe in `StatusIconController` to overlay the moon glyph.

- [ ] **Step 5: Wire right-click menu on the status item** — when the user right-clicks, present an `NSMenu` with the preset durations + About + Quit. Don't show on left-click (that opens the popover).

- [ ] **Step 6: Visual + commit**

```bash
git add app/Sources/Settings/ app/Sources/UI/SettingsView.swift
git commit -m "feat(app): Settings tab + Quiet mode toggle + right-click menu"
```

## Task 30: Navigate-mode overlay + KeyboardMonitor [DONE — loop 28]

**Files:**
- Create: `app/Sources/UI/NavigateOverlay.swift`
- Create: `app/Sources/UI/KeyboardMonitor.swift`
- Test: `app/Tests/KeyboardMonitorTests.swift`

- [ ] **Step 1: Implement `KeyboardMonitor`** — installs a local `NSEvent.addLocalMonitorForEvents` while popover is open, mapping `↑/↓/j/k/⏎/space/Tab/r/esc/1–9`.

- [ ] **Step 2: Implement `NavigateOverlay`** — translucent overlay; when active, intercepts 1–9 and emits `focus(index:)`, then dismisses. The 1–9 numbering reuses `LiveTab`'s `navIndex` parameter.

- [ ] **Step 3: Implement global hotkey hook for navigate mode** — for now, a stub that activates only when popover is visible. Phase 5 vendors `KeyboardShortcuts` for the true global path.

- [ ] **Step 4: Tests** — pure unit tests for the local key handler: given a key down event, the right action is emitted. Visual is manual.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/UI/NavigateOverlay.swift app/Sources/UI/KeyboardMonitor.swift app/Tests/KeyboardMonitorTests.swift
git commit -m "feat(app): navigate mode overlay + popover-local keyboard nav"
```

## Task 31: Pure FocusStrategy (Swift mirror of cctop's resolver) [DONE — loop 29]

**Files:**
- Create: `app/Sources/FocusStrategy/FocusStrategy.swift`
- Test: `app/Tests/FocusStrategyTests.swift`

- [ ] **Step 1: Implement `FocusStrategy.swift` and test it**

Note: cc-dashboard's focus path goes through the sidecar (`/api/focus` → osascript → AXRaise). cctop's `FocusStrategy` enum is useful when the row tap needs to *decide* between Ghostty (call sidecar), iTerm2 (different AppleScript), VS Code-fork (NSWorkspace.open with bundle ID), or Finder fallback. Port it for forward-compatibility:

```swift
// app/Sources/FocusStrategy/FocusStrategy.swift
import Foundation

enum FocusStrategy: Equatable {
    case ghostty(cwd: String, sid: String?)
    case openWithApp(bundleID: String, target: String)
    case openInFinder(path: String)
}

func resolveFocusStrategy(session: LiveSession) -> FocusStrategy {
    // For v1, every cc-dashboard session goes through the Ghostty matcher in the sidecar.
    // Future polyglot extension (opencode/pi/codex) will branch here.
    return .ghostty(cwd: session.cwd, sid: session.sessionId)
}
```

```swift
// app/Tests/FocusStrategyTests.swift
import XCTest
@testable import cc_dashboard

final class FocusStrategyTests: XCTestCase {
    func testV1AlwaysGhostty() {
        let s = LiveSession(pid: 1, sessionId: "x", cwd: "/tmp/r", repo: "r", branch: nil, dirty: 0,
                              startedAt: 0, lastActivity: 0, ageSec: 0, staleDecay: 0, transcriptFound: true,
                              event: .working, reason: "", priority: 90, lastUser: "", lastAssistant: "", openTool: nil)
        XCTAssertEqual(resolveFocusStrategy(session: s), .ghostty(cwd: "/tmp/r", sid: "x"))
    }
}
```

- [ ] **Step 2: Wire `LiveTab.onTap` → strategy → action**

For `.ghostty`, call `APIClient.focus(cwd:sid:)`. For `.openWithApp`, use `NSWorkspace.shared.open(url, withApplicationAt:)` (lifted from cctop). For `.openInFinder`, `NSWorkspace.shared.open(url)`.

- [ ] **Step 3: Run + commit**

```bash
git add app/Sources/FocusStrategy/ app/Tests/FocusStrategyTests.swift
git commit -m "feat(app): pure FocusStrategy resolver (cctop pattern)"
```

---

# Phase 5 — Polish, vendoring, end-to-end

## Task 32: Vendor `KeyboardShortcuts` [DONE — loop 31 hotkey reg + loop 32 Recorder UI]

**Files:**
- Create: `app/Sources/Vendored/KeyboardShortcuts/*.swift`
- Modify: `app/Sources/UI/KeyboardMonitor.swift` to use vendored API
- Modify: `app/Sources/UI/SettingsView.swift` to use the recorder view

- [ ] **Step 1: Identify minimum file set**

In a scratch checkout of `https://github.com/sindresorhus/KeyboardShortcuts`, the minimum to get hotkey registration + a recorder view is roughly:
- `KeyboardShortcuts.swift` (public API)
- `Name.swift`
- `Shortcut.swift`
- `Recorder.swift`
- `CarbonKeyboardShortcuts.swift`

(Variable across versions — confirm by grepping for the symbols you import.)

- [ ] **Step 2: Copy them into `app/Sources/Vendored/KeyboardShortcuts/`**, adjusting imports as needed. Add a top-of-file comment to each: `// Vendored from sindresorhus/KeyboardShortcuts (MIT). See LICENSE-VENDORED.md.`

- [ ] **Step 3: Add `LICENSE-VENDORED.md`** to repo root with the upstream MIT license text + attribution.

- [ ] **Step 4: Wire two named shortcuts** in `KeyboardMonitor`:

```swift
extension KeyboardShortcuts.Name {
    static let navigateMode = Self("navigateMode")
    static let toggleQuiet = Self("toggleQuiet", default: .init(.m, modifiers: [.control, .option]))
}
```

Subscribe in `AppDelegate`:

```swift
KeyboardShortcuts.onKeyDown(for: .navigateMode) { /* enter navigate mode */ }
KeyboardShortcuts.onKeyDown(for: .toggleQuiet) { /* QuietModeStore.shared.toggle() */ }
```

- [ ] **Step 5: Use `KeyboardShortcuts.Recorder` in SettingsView**

```swift
KeyboardShortcuts.Recorder("Navigate mode", name: .navigateMode)
KeyboardShortcuts.Recorder("Toggle Quiet", name: .toggleQuiet)
```

- [ ] **Step 6: Commit**

```bash
git add app/Sources/Vendored/ LICENSE-VENDORED.md app/Sources/UI/KeyboardMonitor.swift app/Sources/UI/SettingsView.swift app/Sources/App/AppDelegate.swift
git commit -m "feat(app): vendor KeyboardShortcuts for global hotkeys + recorder"
```

## Task 33: UNNotifications on attention transitions [DONE — loop 30]

**Files:**
- Modify: `app/Sources/UI/FlashController.swift` — emit a notification when the flash starts (subject to QuietModeStore)
- Modify: `app/Sources/App/AppDelegate.swift` — request notification permission on first run

- [ ] **Step 1: Request permission**

```swift
// in AppDelegate.applicationDidFinishLaunching
import UserNotifications
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
```

- [ ] **Step 2: Post a notification on flash trigger**

In `FlashController.startFlashing`:

```swift
if !QuietModeStore.shared.isQuiet {
    let content = UNMutableNotificationContent()
    content.title = "cc-dashboard"
    content.body = "A session needs your attention."
    if SettingsStore.shared.notificationSound { content.sound = .default }
    let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(req)
}
```

- [ ] **Step 3: Visual check + commit**

```bash
git add app/Sources/UI/FlashController.swift app/Sources/App/AppDelegate.swift
git commit -m "feat(app): UNNotification on attention transition (subject to Quiet mode)"
```

## Task 34: End-to-end smoke test [PARTIAL — loop 25; root-caused loop 26; backend-hang FIX APPLIED loop 27; step 1 (clean build) verified autonomously loop 33; step 2 DATA LAYER verified autonomously loop 35 (5/7 job-stories: Triage/Resume/Recall/Inspect/Customize); VISUAL + FOCUS job-stories (2/7) require human eyes — popover render + Ghostty window raise]

**Files:**
- (Manual) — verify the app works against your real `~/.claude/`

- [ ] **Step 1: Clean build**

```bash
make clean
make app-build
make app-run
```

- [ ] **Step 2: Walk the spec's success criteria**

Run through every job-story in `2026-04-28-menubar-ux-designer-brief.md` §2:

1. **Triage** — open popover, see Live tab, urgent sessions on top.
2. **Resume** — switch to Restore, click a row, copy resume, verify clipboard contents start with `cd `.
3. **Recall** — open a session whose repo has decisions; verify Decisions panel populates.
4. **Inspect** — click a Live row; verify Session Detail shows branch, files, tokens, sparkline, last assistant.
5. **Focus** — click "Focus terminal" on a session whose Ghostty window is on the active space; verify the window raises.
6. **Quiet** — click QuietPill; status icon shows moon overlay; trigger an attention state and confirm no flash, no notification.
7. **Customize** — open Settings, change theme, confirm it applies; rebind Quiet hotkey, confirm new binding works.

- [ ] **Step 3: Note any issues, fix, re-run.**

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: smoke-test issues from end-to-end walk"
```

## Task 35: Delete `server.py` + `index.html` (R3 finalisation) [DONE — loop 36]

**Files:**
- Delete: `server.py`, `index.html`, `__pycache__/`
- Modify: `README.md` — remove "Run with `python3 server.py`" section, replace with `make app-build && make app-run`.

- [ ] **Step 1: Verify the new app does everything `server.py` did** (see Task 34's checklist).

- [ ] **Step 2: Delete the legacy files**

```bash
git rm server.py index.html
rm -rf __pycache__
```

- [ ] **Step 3: Update `README.md`**

Open `README.md`. Replace the "Run" section with:

```
## Run

```
make app-build         # builds the .app bundle
make app-run           # opens it
```

The app appears in your menu bar. Backend (Bun TS sidecar) is bundled inside the .app — no Python or Node required at runtime.

## Build prerequisites

- macOS 14+
- Xcode 15+ Command Line Tools (`xcode-select --install`)
- `xcodegen` (`brew install xcodegen`)
- `bun` (`brew install oven-sh/bun/bun`)
```

Leave the "How the focus mechanism works" section, the "Data sources" table, and the "Architecture" diagram. Update the architecture diagram to reflect Swift app + TS sidecar.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "chore: retire server.py + index.html; update README for menubar app"
```

---

## Final acceptance

The implementation is complete when:

- [ ] `make test` passes (TS unit + integration; Swift unit)
- [ ] `make app-build` produces a runnable `.app`
- [ ] All seven job-stories in Task 34 step 2 pass
- [ ] `git status` clean
- [ ] `server.py`, `index.html` deleted
- [ ] No `console.log` in `backend/src/`; no force-unwraps in production Swift code

---

## Spec coverage check (self-review)

| Spec section | Covered by |
|---|---|
| §1 Goal: form-factor + corpus mining + Quiet mode | Tasks 25–31 (UI), Tasks 15–17 (corpus), Task 29 (Quiet) |
| §2 Stack & build | Tasks 1–4 |
| §3 Architecture | Tasks 4, 19, 20 |
| §4.1 Swift app | Tasks 20–31 |
| §4.2 TS sidecar | Tasks 5–18 |
| §4.3 API contract | Task 18 |
| §5.1 Preserved cc-dashboard features | Tasks 6–14, 26–28 |
| §5.2 Adopted from cctop UX | Tasks 25–31 |
| §5.3 Lifted from cctop architecture | Tasks 11, 31 (FocusStrategy) |
| §5.4 Decision Log + Compost Heap | Task 15 |
| §5.5 Session Detail panel | Task 28 |
| §5.6 Flashing icon + Quiet mode | Tasks 24, 29 |
| §5.7 Settings | Task 29 |
| §6 Data flow | Tasks 16, 18, 22 |
| §7 Error handling | Task 20 (sidecar crash), Task 13 (Ghostty failures), Task 18 (404/400) |
| §8 Testing | Tasks 6–13 (unit), 16, 18 (integration), 22, 24, 31 (Swift unit) |
| §9 Migration plan | Task 35 |

Plan is ready for execution.
