# cc-dashboard menu bar — UX Designer Brief

**For**: visual / interaction designer producing the final design (Figma or equivalent)
**Date**: 2026-04-28
**Companion technical spec**: `2026-04-28-menubar-conversion-design.md` (read for context, not a design doc)

---

## 1. What the product is

A macOS menu bar app that helps a power user manage many concurrent **Claude Code** terminal sessions. The user runs 5–15 AI coding sessions at once and the app's job is to tell them, at a glance:

- Which session needs my attention next?
- What was I doing in this session?
- Did I already answer this kind of question for this repo?

The app lives as an icon in the macOS menu bar (top right, near the clock). Click → popover. Some sessions are urgent (waiting for permission, broken). Some are working. Some are idle. The visual job is to make that hierarchy obvious without screaming.

**Mood**: calm operator's console. Think air-traffic control or a hospital nursing station — not a notification center, not a dashboard. Information density is OK; visual noise is not.

---

## 2. Primary user job-stories

Use these to pressure-test every screen and interaction.

1. **Triage** — When I'm context-switching between sessions, I want to see at a glance which one needs me next, so I can decide where to look without reading every transcript.
2. **Resume** — When I closed a terminal yesterday, I want to find where I left off and copy a resume command, so I can pick up without losing context.
3. **Recall** — When I'm starting a new session on a familiar repo, I want to see my prior decisions for that repo, so I don't re-answer the same questions.
4. **Inspect** — When I open a session, I want to see branch + token usage + files touched + activity over time, so I can decide whether to keep going, fork, or stop.
5. **Focus** — When I'm in a coding drill and don't want interruptions, I want a one-click way to silence the app, so I'm not pulled out of flow.
6. **Customize** — When the defaults don't fit my workflow, I want to change theme, hotkeys, polling cadence, and notification settings.

---

## 3. Information architecture

```
Menu bar status icon (always visible)
  │
  ├─ tap → Popover
  │   ├─ Tab: Live           ← default
  │   ├─ Tab: Restore
  │   └─ Tab: Settings
  │
  └─ right-click → Context menu (Quiet mode presets, About, Quit)

From any list row:
  → push → Session Detail screen (back arrow returns)
```

Three top-level tabs. One detail screen reachable by drilling in. No modals (settings is a tab, not a sheet).

---

## 4. Screen inventory

Each screen has multiple **states**. A complete design covers every listed state.

### 4.1 Status icon (always visible in menu bar)

The single most important visual surface. Should communicate, just from the icon, **how many sessions need me and how urgently**.

States:
- **Idle / all clear** — neutral baseline glyph
- **Working** — at least one session is mid-tool, no attention needed → neutral glyph + small activity indicator
- **Needs attention (1)** — exactly one session in `permission-pending`, `tool-failed`, or `ask` → glyph + small badge
- **Needs attention (n)** — multiple → glyph + count badge
- **Flashing** — newly transitioned into needs-attention → 1 Hz two-image swap (alert ↔ baseline) for up to 30 s
- **Quiet mode active** — moon overlay on glyph; flashing suppressed; data still updates
- **Backend down** — red/error variant; tooltip explains
- **Loading (cold start)** — grey/neutral until backend health-checks pass

**Designer questions**:
- What's the baseline glyph? cctop uses a stylized "cc"; we want our own. Should reflect "many sessions in flight" — maybe a small grid, or stacked layers.
- What does "needs attention" look like at 9pt-tall in the menu bar? Color? Number?
- How does the moon overlay sit on top without making the icon illegible?

### 4.2 Popover — Live tab (default)

The triage view. Sessions ranked top-to-bottom by urgency.

Layout regions:
- **Header** — small title or branding strip; Quiet-mode pill toggle (Active ⚡ / Quiet 🌙); maybe count summary
- **Session list** — scrollable, one row per live session
- **Footer** — gear (Settings), nav-mode hint, maybe a "last refreshed" indicator

Session row anatomy (every row needs):
- Repo name
- Branch (current)
- Status indicator (color + icon, mapped to event type)
- Status reason (short string: "running Bash", "tool failed: pytest", "ready for next instruction")
- Relative time since last activity ("3m ago")
- Visual urgency cue (border, background, badge)

States:
- **Empty** — "No live sessions. Start one with `claude` in a terminal."
- **Loading** — first 1–2 s after launch while sidecar warms up
- **Populated** — rows present, top row is most urgent
- **Error** — backend down, "Backend isn't responding. [Retry] [View log]"
- **Navigate mode active** — every visible row gets a numbered badge (1–9); rows >9 hidden or grayed
- **Hovered row** — affordance shift to signal clickability
- **Focused row** (keyboard nav) — selection highlight

### 4.3 Popover — Restore tab

The recovery view. Recent sessions per repo from the last 14 days. Used after crashes, end-of-day, or "what was I doing on repo X yesterday?"

Layout:
- **Header** — same Quiet-mode pill
- **Repo list** — one row per repo, sorted by most-recent activity
- **Side panel** (collapsible, right side or below) — "where I left off" detail for the selected repo

Repo row anatomy:
- Repo name
- Last activity time
- Branch + dirty count
- Last classified event (from the last session)
- Dim if that cwd no longer exists on disk

Side panel anatomy:
- Recent prompts (last 5)
- Claude's last message
- Open tool at session end (if any)
- Git diff stat (if uncommitted)
- Action row: **Resume command** (copies `cd && claude --resume`), **Fork summary** (copies markdown), **Open in IDE**

States:
- Empty (no recent sessions in 14 days)
- Populated, no row selected (side panel shows hint)
- Populated, row selected (side panel shows detail)

### 4.4 Popover — Settings tab

In-popover settings (no separate window). Sections:

1. **Appearance** — theme (4 options × dark/light), poll interval
2. **Hotkeys** — navigate mode (rebind), quiet mode (rebind)
3. **Notifications** — flash on attention (toggle), flash duration cap (slider), notification sound (toggle), custom mute durations (list)
4. **Tools** — IDE override (which app to open with), Ghostty Accessibility status (with deeplink to System Settings)
5. **About** — version, last health check, log file path

Each section is collapsible OR shown as a single scrollable form — designer choice.

### 4.5 Session Detail (push-navigation from a Live row)

The "what's happening in this session" deep-dive. Reached by tapping a Live row.

**Header**:
- Back arrow ← (returns to Live)
- Repo · branch (current)
- Session age, source (cc / opencode / pi / codex — usually cc)

**Sections (top to bottom)**:

1. **Branch timeline** — small horizontal timeline showing branch changes during this session ("main → feat/auth → feat/auth-tests"). Each segment is clickable to copy or filter.
2. **Files changed this session** — list, deduped, sorted by most-recent edit. Each item: filename, parent path, edit count, last touch time.
3. **Token usage** — three numbers + a bar:
   - Input tokens (total)
   - Cached read tokens (separate; usually large)
   - Output tokens
   - 200k context utilization bar (model-aware: detect from transcript, fall back to 200k)
4. **Load over time** — small sparkline of `tool_use` per minute over the session lifetime. Communicates "active" vs "stalled" sessions.
5. **Last assistant message** — text block with the most recent assistant turn (truncated, expandable)
6. **Open tool** — if a tool is currently running, name + args
7. **Decisions panel** (per-repo Q/A pairs) — list of "Q: ...? A: ..." pairs deduped from this repo's history. Action: prepend to clipboard for next session.
8. **Action row** — Focus Terminal, Copy Resume, Copy Fork, Open in IDE

States:
- Loading (data fetch in flight)
- Populated
- Sparse (new session with little data) — show what's there, don't pad
- Error (data fetch failed)

### 4.6 Navigate mode overlay

A short-lived modal layer triggered by a global hotkey. Overlays numbered badges (1–9) on top of the visible Live rows. User presses the number → app focuses that session's terminal → overlay dismisses.

States:
- Inactive (default)
- Active (badges visible, all other interactions paused)
- Active + waiting for second key (after pressing a digit)

Designer questions:
- What does the overlay look like? Translucent dark wash + bold numbers? Inline badges with no wash?
- What if there are >9 sessions? Top 9 by rank? Numbered 1–9, others ungraded?
- How does the overlay close — Escape? Any non-digit key?

### 4.7 Right-click context menu (status icon)

Native macOS `NSMenu`. Items:
- Mute for 30 min
- Mute for 1 hour
- Mute for 4 hours
- Mute until tomorrow 9 AM
- Mute until I unmute
- ──
- About cc-dashboard
- Quit

This is the only screen that's vanilla macOS chrome — designer doesn't need to style it, but should confirm the copy.

### 4.8 Empty + permission states (cross-cutting)

Three blocking-empty states the user might hit on first run:

1. **No `~/.claude/` directory** — "Looks like Claude Code isn't installed. [Install instructions]"
2. **Accessibility permission not granted** (needed for Ghostty focus) — banner with deeplink to System Settings → Privacy → Accessibility
3. **Notifications permission not granted** — banner with deeplink

Designer needs to decide: how prominent are these, where do they appear, what's the recovery affordance?

---

## 5. Interaction inventory

### 5.1 Mouse / trackpad
- Click status icon → open / close popover
- Right-click status icon → context menu
- Click Live row → push to Session Detail
- Click action button (Focus / Resume / Fork / Open in IDE) → execute
- Drag popover header → detach into a draggable floating panel; double-click header to snap back
- Click tab → switch tab
- Click gear → Settings tab
- Click Quiet-mode pill → toggle Quiet (or open submenu for duration)

### 5.2 Keyboard (popover-local)
- `↑` `↓` / `j` `k` — move selection in current list
- `⏎` — primary action on selection (Live: Focus terminal; Restore: copy resume command; Detail: focus terminal)
- `space` — jump selection to top row
- `Tab` — toggle Live / Restore
- `r` — force refresh
- `esc` — close popover OR exit Navigate mode

### 5.3 Keyboard (global, work from any app)
- Navigate hotkey (default unset; user binds in Settings) — overlay 1–9 badges, then digit jumps
- Quiet hotkey (default `⌃⌥M`, rebindable) — toggle Quiet mode

### 5.4 Auto-behaviors
- Status icon flashes when a session newly enters needs-attention; auto-stops at 30 s
- Notification posted on the same trigger (subject to Quiet mode)
- Polling refresh every 2 s while popover open (quieter when closed)
- Popover detaches if user drags the header

---

## 6. Visual urgency taxonomy

The single most important design decision: how do the five session states differentiate visually? Suggested ordering, designer to assign visual treatment:

| State | Meaning | Suggested urgency |
|---|---|---|
| `permission-pending` | Claude is waiting for the user to approve a tool | **Highest** — bright accent, possibly pulsing |
| `tool-failed` | A tool errored and Claude hasn't responded yet | High — distinct color from permission-pending |
| `ask` | Claude ended its turn with a question | Medium-high |
| `working` | A tool is currently running | Medium — calm, "in motion" cue |
| `idle-after-complete` | Done, waiting for user input | Low |
| `clear` | Nothing pending | Lowest — neutral |

Plus a **staleness decay** on top: a session that's been in any state for > 30 min loses urgency (icon dims, deprioritized in sort).

Designer questions:
- Color palette per state? Color-blind-safe?
- Iconography per state? Words and color? Icon and color?
- How does staleness manifest visually without losing the state info?

---

## 7. Component inventory (reusable atoms)

These appear across multiple screens. Designer should produce a single visual treatment per component.

- **Status badge** — color + icon + optional count, used in status bar icon and per-row indicators
- **Session row** — Live and Restore both use a list-row primitive
- **Repo header** — name + branch + dirty count, used in rows and Detail header
- **Quiet-mode pill** — popover header
- **Numbered badge** — Navigate mode overlay (1–9)
- **Section header** — Detail screen sections, Settings sections
- **Action button row** — Focus / Resume / Fork / Open in IDE; consistent across Restore side panel and Session Detail
- **Sparkline** — small inline chart for load history; Detail screen only for now, future projections may reuse
- **Token usage bar** — context-window utilization; Detail screen
- **Banner** — permission errors and other system-level alerts; full-width strip
- **Empty state** — illustration + copy + CTA; reused across all empty list states

---

## 8. Themes

Four color palettes × dark/light = 8 total themes. Each must work for every screen. Suggested starting points (designer can replace):

- **Claude** — cream / soft black, accent in classic Anthropic orange
- **Tokyo Night** — deep blue, magenta, cyan
- **Gruvbox** — warm earth tones, amber
- **Nord** — cool grey-blue, ice

Each theme defines:
- Background (popover, row, banner)
- Foreground (primary, secondary, tertiary text)
- Accent (interactive elements, active state)
- Urgency colors per session state (5 of them, color-blind-safe)
- Status icon glyph variant (template image, monochrome)

Reference: cctop's themes (look at `cctop/menubar/CctopMenubar/Models/AppTheme.swift` and `Color+Theme.swift`).

---

## 9. Microcopy that needs writing

Empty states, error states, confirmations, button labels. Don't lift cctop's copy verbatim — write fresh, in our voice (calm, direct, no exclamation marks).

Specific strings the designer should propose:
- "No live sessions" empty state on Live tab
- "No recent sessions in the last 14 days" on Restore tab
- "Looks like Claude Code isn't installed" on missing `~/.claude/`
- Permission-denied banners (Accessibility, Notifications)
- "Backend isn't responding" error
- Action button labels (Focus Terminal vs Jump to Terminal vs Open Terminal — pick one)
- Quiet mode pill states ("Active" / "Quiet" — confirm or replace)
- Tooltip strings for the gear, the Quiet pill, the count badges

---

## 10. References

- **cctop** — `/Users/claudevcheval/Hanalei/cctop/menubar/CctopMenubar/Views/PopupView.swift` and `Views/SessionCardView.swift` for cctop's row layout (one of several valid choices, not a target to copy verbatim).
- **cctop screenshots** — `cctop/docs/menubar-tokyonight-dark.png`, `menubar-light.png`, `menubar-navigate.png`, `menubar-recent.png`, `status-icon.png`, `theme-*.png`. Useful as reference for what the user is comparing against.
- **Existing cc-dashboard UI** — `/Users/claudevcheval/Hanalei/cc-dashboard/index.html`. The current browser-based UI; gives a sense of the data and the user's existing workflow. Don't copy the styling — designer is making a new product.

---

## 11. Out of scope for design (v1)

- Onboarding flow / first-run wizard — minimal, existing macOS permission prompts only
- Cross-platform UI variants — macOS only
- Marketing site / landing page
- Tray icon animation beyond simple two-image flash
- Auto-mute when Cursor / VS Code is frontmost (deferred to v2)
- Native notification design (uses macOS default notification UI)

---

## 12. What the designer hands back

A complete Figma file (or equivalent) with:

- Each screen × each listed state — fully designed
- Each component in the inventory (§7) — single source of truth
- All four themes × dark/light — applied to at least the Live tab and Session Detail
- Status icon glyph + all states (idle, working, attention, flashing, quiet, error, loading)
- Microcopy for every string in §9
- Interaction notes / annotations for non-obvious behaviors (drag to detach, navigate-mode overlay timing, flash cadence)

A short rationale doc (1–2 pages) explaining color choices for the urgency taxonomy and any deviations from this brief.
