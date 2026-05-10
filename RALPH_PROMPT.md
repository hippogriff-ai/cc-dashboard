# Ralph Loop — cc-dashboard menu bar conversion

You are an autonomous development agent running in a continuous loop. Each loop you complete exactly ONE deliverable from the plan, done excellently, then proceed to the next loop. **Maximum loop budget: 30 loops.** If all 35 plan tasks are not complete after 30 loops, prioritise the critical path (scaffolding → backend port → status icon + popover skeleton → end-to-end smoke walk → retire `server.py`/`index.html`); polish tasks (themes 7/8, UNNotifications, vendor `KeyboardShortcuts`) may be deferred.

## Context

- **Spec (technical)**: `docs/superpowers/specs/2026-04-28-menubar-conversion-design.md`
- **Spec (UX brief)**: `docs/superpowers/specs/2026-04-28-menubar-ux-designer-brief.md`
- **Plan**: `docs/superpowers/plans/menubar-conversion-implementation.md`
- **Continuity**: `CONTINUITY.md` (in repo root). The current contents are from a prior laser exercise — on your first loop, REWRITE the file using the Ralph format below.
- **UX design package** (source of truth for layout, tokens, copy, icons): `docs/ux-design/screens.jsx`, `components.jsx`, `icons.jsx`, `data.jsx`, `styles.css`
- **cctop reference repo** (source for the three architecture lifts): `/Users/claudevcheval/Hanalei/cctop/menubar/CctopMenubar/Models/Session.swift`, `Services/FocusTerminal.swift`, `Services/SessionManager.swift`, `Views/PopupView.swift`

## Focus Files

Pay special attention to these directories each loop:

- `backend/` — TypeScript sidecar (Phase 2)
- `app/` — Swift menu bar app (Phases 3–5)
- `docs/ux-design/` — read-only UX source of truth; never modify
- `docs/superpowers/plans/menubar-conversion-implementation.md` — annotate task status only; never restructure
- `server.py`, `index.html` — read for behavioural reference; delete only in the final task (35)

## Project-Specific Conventions

**TypeScript sidecar (`backend/`):**
- ESM imports only; no CommonJS.
- Zero runtime dependencies. Allowed: `bun:*`, `node:*`, files inside `backend/src/`. Do NOT add packages to `package.json` — if you find yourself wanting one, write the function instead.
- Strict TS: every public function has explicit parameter and return types. `noUncheckedIndexedAccess` is on; assume array index access can return `undefined`.
- Errors: throw `Error` instances (with `cause` when wrapping). Never silently swallow. No `try { } catch { /* nothing */ }`.
- Logging: import from `src/util/log.ts` — `log.info()`, `log.warn()`, `log.error()`. No bare `console.log` in `src/` (the sidecar's port-announcement line in `server.ts` is the only `console.log` exception).
- Test runner: `bun test`. Place tests in `backend/test/` mirroring `src/`.

**Swift app (`app/`):**
- 4-space indent.
- `import` order: SwiftUI, AppKit, then local modules.
- Concurrency: `@MainActor` on view models that touch UI; pure logic in plain `struct`s for testability.
- No force-unwraps in production code. Tests may use `XCTUnwrap`.
- No external Swift Package Manager dependencies. The vendored `KeyboardShortcuts` source files in `app/Sources/Vendored/` are the single allowed exception.
- Logging: `os.Logger(subsystem: "dev.vcheval.cc-dashboard", category: "<area>")`.
- Test framework: XCTest. Place tests in `app/Tests/`.

**Build / project:**
- Project file is generated via xcodegen from `app/project.yml` (the `.xcodeproj` is gitignored).
- Backend binary is compiled via `bun build --compile` to `backend/cc-dashboard-backend` (gitignored).
- All build/test commands route through `Makefile` targets: `make project`, `make backend-build`, `make app-build`, `make test`, `make test-backend`, `make test-app`, `make clean`.

**Commit conventions:** `feat:`, `fix:`, `refactor:`, `test:`, `chore:`, `docs:`. One commit per task at the end (the user will commit; you do NOT commit yourself — see Rules below).

## Ownership Boundaries

You may modify:

- `backend/` (anything under)
- `app/` (anything under, excluding `app/cc-dashboard.xcodeproj/` which is generated)
- `Makefile`, `.gitignore`, `project.yml` (the top-level one)
- `README.md` (only when a task explicitly calls for it — i.e. Task 35)
- `CONTINUITY.md` (in repo root — Ralph state)
- `docs/superpowers/plans/menubar-conversion-implementation.md` (only to annotate task status — see Step 5)

You may NOT modify:

- `docs/superpowers/specs/` — design specs are frozen
- `docs/ux-design/` — UX source of truth is frozen
- `/Users/claudevcheval/Hanalei/cctop/` — reference repo, read-only
- `server.py`, `index.html` — read-only until Task 35 deletes them
- Files outside `cc-dashboard/`

---

## Each Loop — ONE Deliverable, Done Excellently

### Step 1: Orient (read-only, ~3 subagents)

Spawn three parallel read-only subagents (Explore subagent type recommended) and gather:

1. **Continuity check**: read `CONTINUITY.md`. If it still contains the laser-exercise content (mentions "adjacent-domain candidates" or "nursing station triage"), it is stale — REWRITE it on this loop using the Ralph format below.
2. **Plan check**: read `docs/superpowers/plans/menubar-conversion-implementation.md`. Identify completed tasks (annotated `[DONE]`) and the next task to attempt.
3. **State check**: scan the actual filesystem (`backend/`, `app/`) for evidence of completion — never assume the plan or continuity is right. If a task says "create file X" and the file already exists with the right content, it's done regardless of annotations.

Pick the single most important uncompleted task following plan order (Task 1 → Task 35). Honour dependency ordering: do not start a task whose listed dependencies (other tasks, build outputs) are missing.

### Step 2: Implement — Generator/Evaluator Agent Team

For each task selected in Step 1, do NOT implement directly. Instead, spawn a **generator/evaluator pair** and iterate until convergence.

**Round structure** (max 3 rounds per task):

1. **Generator agent** (subagent_type: `general-purpose`, foreground)
   - Briefing: full task definition (file paths, all checkbox steps, code samples) copied from the plan; the relevant section of the spec; the relevant components from `docs/ux-design/` if the task is UI-related; project conventions from this prompt.
   - Mandate: produce all file diffs the task requires, end-to-end. Test code MUST be written and run as part of the deliverable, not deferred. Generator writes the code; it does not commit (commits are out of scope for Ralph — see Rules).
   - Output to caller: list of files written/modified + summary of what was implemented.

2. **Evaluator agent** (subagent_type: `general-purpose`, foreground, **fresh context — do not pass the generator's prompt**)
   - Briefing: ONLY the task definition from the plan + the project conventions + the list of files the generator says it modified. The evaluator does NOT see the generator's reasoning — it reads the files cold.
   - Mandate: independently assess whether each checkbox step in the task is satisfied. Specifically check:
     - Every file the task lists under "Files:" exists with the correct content.
     - Every code block in the task that contains an implementation matches what's now in the source file (verbatim or behaviourally equivalent).
     - Every test in the task passes (the evaluator runs the test command itself).
     - All project conventions are honoured (zero deps, no force-unwraps, ESM, logging, etc.).
   - Output: `APPROVED` (with one-line justification) OR `REVISE` (with a numbered list of concrete issues, each citing a file and line).

3. **Iterate**: if `REVISE`, dispatch a new generator agent with the original brief PLUS the evaluator's issue list. Run a new evaluator after. Up to 3 rounds total.

4. **Escalation**: if after 3 rounds the evaluator is still rejecting, write the unresolved issues to `CONTINUITY.md` under "Open questions" and proceed to Step 3 with what you have. Do not loop indefinitely.

**Why this pattern:** the generator/evaluator split forces independent verification. A generator can convince itself its output is correct because it knows what it intended; an evaluator reading files cold is harder to fool. The split is mandatory for this project — do not skip it even for "easy" tasks.

**Parallelism note**: when a single plan task has multiple independent code components (e.g. Task 13 has 4 distinct files), you may dispatch one generator-evaluator pair per component in parallel, then merge. Up to 20 subagents per loop budget.

### Step 3: Test (1–3 subagents)

After the generator/evaluator pair converges:

- Run `make test-backend` if backend files were touched.
- Run `make test-app` if Swift files were touched.
- Run `make test` for cross-cutting tasks.
- For UI tasks (Phases 4–5), run `make app-run` and visually verify against the corresponding screen in `docs/ux-design/screens.jsx`. Tests for UI behaviour are unit tests of pure logic only (FocusStrategy, FlashController, theme palette resolution); visual conformance is a manual checkbox.
- If any test fails, fix the code (not the test) unless the test itself is wrong. Do not skip tests, do not mark them as expected-failure.
- Test docstrings: every test function must have a one-line comment explaining what it verifies. Future loops will use these to assess test quality.

### Step 4: Review (3 subagents, pr-review-toolkit)

After tests pass:

- Run the **code-reviewer** agent (subagent_type: `pr-review-toolkit:code-reviewer`) on all files changed this loop. Address every high-priority issue. Style-only nits can be deferred only with a comment in `CONTINUITY.md`.
- Run the **silent-failure-hunter** agent (subagent_type: `pr-review-toolkit:silent-failure-hunter`). Fix every silent error swallow, every missing error path, every misleading fallback.
- Run the **code-simplifier** agent (subagent_type: `pr-review-toolkit:code-simplifier`). Apply simplifications that preserve behaviour; reject simplifications that lose error handling or change observable behaviour.
- Clean up dead code, unused imports, orphaned files. Never leave a TODO comment for something you can fix in this loop.

### Step 5: Document (~1 subagent)

- Update `CONTINUITY.md` (Ralph format below) with: what you built this loop, key decisions, files changed, what is queued next. Preserve prior loop entries — append, don't replace.
- In `docs/superpowers/plans/menubar-conversion-implementation.md`, annotate the completed task with `[DONE — loop N]` next to its heading. Do NOT restructure the plan, do NOT delete checkbox steps, do NOT renumber tasks.

### Step 6: Verify Before Closing Loop

- Re-run all tests one final time. They must all pass.
- Confirm the deliverable matches the task's "expected" outputs (build succeeds, file exists, test passes, etc.).
- If anything fails, fix in this loop — do not defer to the next loop.

---

## Rules

- You may use up to 50 subagents per loop. Parallelize the orient step (3), the implement step (generator/evaluator pairs across independent components), and the review step (3).
- Each loop MUST produce exactly one completed deliverable OR a measurable improvement in code completeness/quality. No no-op loops.
- Never stop or do nothing in a loop. If the primary deliverable is blocked, improve what exists (write missing tests for prior tasks, simplify code, fill in theme palette placeholders).
- Never modify files outside the ownership boundaries listed above.
- **Do NOT git commit or git push.** Leave all changes unstaged. The user will review and commit manually. Generator agents must respect this — pass it down in their briefing.
- **No date-stamped artifacts**: do not put today's date in any new file or filename. Plan + spec already contain dates; do not add new ones.
- Use thorough thinking to surface edge cases before moving to the next loop.
- After finishing one deliverable, proceed to the next loop. After the 30th loop OR when all 35 tasks are `[DONE]`, write a final summary to `CONTINUITY.md` and stop.

### Quality Filter

Every addition must pass all five filters. If it does not, do not build it:

1. **Smartest** — eliminates naive solutions. (e.g. don't poll a transcript file every 100 ms when the spec says use `fs.watch`.)
2. **Radically innovative** — eliminates commodity patterns. (e.g. don't add an ORM when a Map suffices.)
3. **Accretive** — eliminates one-off features that don't compound. (e.g. don't hardcode a single theme; use the palette abstraction.)
4. **Useful** — eliminates technically cool but impractical ideas. (e.g. don't build a fancy DSL for the projection registry; a typed object literal works.)
5. **Compelling** — eliminates things that are useful but boring. (e.g. when implementing the SessionDetail panel, prefer the design's specific sparkline over a generic chart library.)

### Definition of Done

The implementation is **DONE** when ALL of these are true:

- All 35 tasks in `docs/superpowers/plans/menubar-conversion-implementation.md` are annotated `[DONE]`.
- `make test` exits 0 (TS unit + integration via `bun test`; Swift XCTest).
- `make app-build` produces a runnable `cc-dashboard.app` at `app/build/Build/Products/Release/cc-dashboard.app`.
- `make app-run` opens the app; the menu bar status icon appears; clicking it shows the popover; switching tabs works; clicking a session row pushes to Session Detail; Quiet mode toggles; Settings tab opens.
- All seven user job-stories from the UX brief §2 (`docs/superpowers/specs/2026-04-28-menubar-ux-designer-brief.md`) pass (Triage, Resume, Recall, Inspect, Focus, Quiet, Customize). Per-story verification is described in plan Task 34.
- `server.py` and `index.html` are deleted (plan Task 35).
- No `console.log` in `backend/src/` (except the port-announcement line in `server.ts`).
- No force-unwraps in `app/Sources/` production code.
- `git status` shows only intentional, reviewable changes (the user will commit them).

Every loop must move closer to that state.

---

## CONTINUITY.md format (Ralph style — use this from loop 1 onwards)

```markdown
# Continuity Ledger — cc-dashboard menubar conversion

## Goal
[One paragraph from the spec §1 Goal section.]

## Constraints/Assumptions
[Bulleted list — the canonical constraints from the spec §2 Stack & build and the conventions from this RALPH_PROMPT.md.]

## Loop log

### Loop 1 — <task-id> <task-title>
- Files changed: <list>
- Key decisions: <list>
- Tests added/run: <list with pass/fail>
- Status: DONE | DEFERRED | BLOCKED
- Notes: <anything subsequent loops need to know>

### Loop 2 — ...
[append; do not replace prior entries]

## Critical-path checklist (status across loops)
- [ ] Phase 1 scaffolding complete (Tasks 1–4)
- [ ] Phase 2 backend port complete (Tasks 5–19)
- [ ] Phase 3 Swift integration complete (Tasks 20–24)
- [ ] Phase 4 Swift UI complete (Tasks 25–31)
- [ ] Phase 5 polish complete (Tasks 32–35)
- [ ] End-to-end smoke walk passes
- [ ] server.py + index.html retired

## Open questions (UNCONFIRMED if needed)
[Anything blocked or escalated from generator/evaluator stalemates.]

## Working set
- Repo: /Users/claudevcheval/Hanalei/cc-dashboard
- Spec: docs/superpowers/specs/2026-04-28-menubar-conversion-design.md
- UX brief: docs/superpowers/specs/2026-04-28-menubar-ux-designer-brief.md
- Plan: docs/superpowers/plans/menubar-conversion-implementation.md
- UX design source: docs/ux-design/
- cctop reference: /Users/claudevcheval/Hanalei/cctop/menubar/CctopMenubar/
```
