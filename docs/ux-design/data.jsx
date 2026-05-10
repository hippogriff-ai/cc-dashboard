// cc-dash mock data + ticking simulation
// Generates realistic-feeling session data and mutates over time.

const REPOS = [
  { repo: "anthropic/claude-code", branch: "feat/permission-prompts", dirty: 4 },
  { repo: "myorg/payments-api", branch: "feat/idempotency", dirty: 12 },
  { repo: "personal/dotfiles", branch: "main", dirty: 0 },
  { repo: "anthropic/cc-dash", branch: "feat/restore-tab", dirty: 7 },
  { repo: "myorg/web-app", branch: "fix/auth-redirect", dirty: 2 },
  { repo: "myorg/payments-api", branch: "feat/refunds-ledger", dirty: 9 },
  { repo: "experiments/sparkline-lab", branch: "main", dirty: 0 },
  { repo: "anthropic/claude-code", branch: "main", dirty: 0 },
  { repo: "myorg/data-pipeline", branch: "feat/dbt-migration", dirty: 18 },
  { repo: "myorg/web-app", branch: "feat/onboarding-v3", dirty: 5 },
  { repo: "personal/blog", branch: "draft/llm-eval", dirty: 3 },
  { repo: "myorg/auth-svc", branch: "main", dirty: 0 },
];

const STATUS_REASONS = {
  "permission-pending": [
    "wants to run Bash: rm -rf node_modules",
    "wants to write src/auth/middleware.ts",
    "wants to run Bash: pnpm install",
    "wants to run Bash: git push --force",
    "wants to edit prisma/schema.prisma",
  ],
  "tool-failed": [
    "tool failed: pytest",
    "tool failed: tsc --noEmit",
    "tool failed: pnpm build",
    "tool failed: cargo test",
    "tool failed: bash exit 1",
  ],
  "ask": [
    "ready for next instruction",
    "asked: which strategy?",
    "asked: should I commit?",
    "asked: rollback or fix forward?",
  ],
  "working": [
    "running Bash: pnpm test",
    "reading src/server/routes",
    "writing src/lib/queue.ts",
    "running Bash: cargo check",
    "running Grep: 'session_id'",
    "running Bash: tsc --noEmit",
  ],
  "idle-after-complete": [
    "completed 3 edits",
    "merged feat branch",
    "all tests passing",
    "diff applied",
  ],
  "clear": ["nothing pending"],
};

let _sessionId = 0;
function makeSession(stateOverride) {
  const r = REPOS[Math.floor(Math.random() * REPOS.length)];
  const states = ["permission-pending", "tool-failed", "ask", "working", "working", "working", "idle-after-complete"];
  const state = stateOverride || states[Math.floor(Math.random() * states.length)];
  const reasons = STATUS_REASONS[state] || ["…"];
  return {
    id: ++_sessionId,
    repo: r.repo,
    branch: r.branch,
    dirty: r.dirty,
    state,
    reason: reasons[Math.floor(Math.random() * reasons.length)],
    lastActivity: Date.now() - Math.floor(Math.random() * 1000 * 60 * 25),
    started: Date.now() - Math.floor(Math.random() * 1000 * 60 * 90) - 1000 * 60 * 5,
    source: "cc",
    inputTokens: Math.floor(8000 + Math.random() * 60000),
    cachedTokens: Math.floor(40000 + Math.random() * 130000),
    outputTokens: Math.floor(2000 + Math.random() * 12000),
    contextLimit: 200000,
    sparkline: Array.from({ length: 32 }, () => Math.floor(Math.random() * 8)),
    files: [
      { path: "src/auth/middleware.ts", edits: 4, lastTouch: Date.now() - 1000 * 60 * 2 },
      { path: "src/lib/session-store.ts", edits: 2, lastTouch: Date.now() - 1000 * 60 * 7 },
      { path: "tests/auth.spec.ts", edits: 6, lastTouch: Date.now() - 1000 * 60 * 12 },
      { path: "prisma/schema.prisma", edits: 1, lastTouch: Date.now() - 1000 * 60 * 18 },
      { path: "src/server/routes/login.ts", edits: 3, lastTouch: Date.now() - 1000 * 60 * 22 },
    ],
    branchHistory: ["main", r.branch],
    lastAssistant:
      state === "permission-pending"
        ? "I need to remove the existing node_modules before reinstalling because the lockfile changed. Can I run `rm -rf node_modules` and then reinstall?"
        : state === "tool-failed"
        ? "The test suite failed with 3 errors in tests/auth.spec.ts. Looks like the new middleware is rejecting requests that don't carry a session cookie. I'll patch the test fixture to include one."
        : state === "ask"
        ? "Two ways to handle this: (1) idempotency keys at the API layer, or (2) database-level uniqueness constraints. I lean toward (1) for clarity. Which would you like me to take?"
        : "Pulling the latest changes and running the test suite to confirm the migration applied cleanly.",
    decisions: [
      { q: "What ORM does this repo use?", a: "Prisma 5 — schema is in prisma/schema.prisma." },
      { q: "Should I write integration tests?", a: "Yes, but only for the public API surface. Skip internal helpers." },
      { q: "Conventional commits?", a: "Yes — feat:, fix:, chore: prefixes." },
    ],
  };
}

function makeInitialSessions(n) {
  // Make sure we have a good mix of states for the demo
  const seeded = [
    "permission-pending",
    "permission-pending",
    "tool-failed",
    "ask",
    "working",
    "working",
    "working",
    "idle-after-complete",
    "idle-after-complete",
  ];
  const out = [];
  for (let i = 0; i < n; i++) {
    out.push(makeSession(seeded[i] || undefined));
  }
  // give them slightly varied timing so the row sort is deterministic-ish
  out.forEach((s, i) => {
    s.lastActivity = Date.now() - i * 1000 * 60 * (i < 3 ? 0.3 : 2);
  });
  return out;
}

// Restore tab — past sessions per repo (last 14 days)
function makeRestoreSessions() {
  const now = Date.now();
  return [
    {
      id: "r1",
      repo: "anthropic/cc-dash",
      branch: "feat/restore-tab",
      dirty: 7,
      lastActivity: now - 1000 * 60 * 35,
      lastEvent: "idle-after-complete",
      lastEventLabel: "Stopped after 14 edits",
      cwdExists: true,
      prompts: [
        "Add a restore tab that shows recent sessions per repo",
        "Use the last 14 days as the cutoff",
        "Side panel should show recent prompts and a resume command",
        "Don't show repos whose cwd no longer exists",
        "Sort by most recent activity",
      ],
      lastAssistant: "Wired the side panel to update on row selection and added a 14-day cutoff filter. Ready for your review.",
      openTool: null,
      diff: { add: 246, del: 38 },
    },
    {
      id: "r2",
      repo: "myorg/payments-api",
      branch: "feat/idempotency",
      dirty: 12,
      lastActivity: now - 1000 * 60 * 60 * 4,
      lastEvent: "tool-failed",
      lastEventLabel: "tsc --noEmit failed",
      cwdExists: true,
      prompts: [
        "Add idempotency keys to /charges and /refunds",
        "Use a Redis-backed dedup store with 24h TTL",
        "Write integration tests covering double-submit",
      ],
      lastAssistant: "tsc found 4 type errors in src/handlers/charges.ts after I added the IdempotencyKey middleware. Want me to relax the type or fix the call sites?",
      openTool: { name: "Bash", args: "tsc --noEmit" },
      diff: { add: 412, del: 87 },
    },
    {
      id: "r3",
      repo: "personal/dotfiles",
      branch: "main",
      dirty: 0,
      lastActivity: now - 1000 * 60 * 60 * 22,
      lastEvent: "ask",
      lastEventLabel: "Asked: which shell?",
      cwdExists: true,
      prompts: [
        "Add a fish prompt with git status",
        "Match the colorscheme of my Ghostty config",
      ],
      lastAssistant: "Do you want me to put the prompt config in ~/.config/fish/config.fish or split it into a separate file you can source?",
      openTool: null,
      diff: { add: 18, del: 4 },
    },
    {
      id: "r4",
      repo: "myorg/data-pipeline",
      branch: "feat/dbt-migration",
      dirty: 18,
      lastActivity: now - 1000 * 60 * 60 * 38,
      lastEvent: "working",
      lastEventLabel: "Tool was running when I closed",
      cwdExists: true,
      prompts: [
        "Migrate the legacy SQL views to dbt models",
        "Keep the same column names so downstream dashboards don't break",
        "Add unit tests using dbt-utils.equality",
      ],
      lastAssistant: "Running dbt build to confirm the new models compile against the staging warehouse.",
      openTool: { name: "Bash", args: "dbt build --select staging" },
      diff: { add: 1840, del: 622 },
    },
    {
      id: "r5",
      repo: "experiments/sparkline-lab",
      branch: "main",
      dirty: 0,
      lastActivity: now - 1000 * 60 * 60 * 24 * 6,
      lastEvent: "idle-after-complete",
      lastEventLabel: "Done — committed and pushed",
      cwdExists: false, // dim row
      prompts: ["Try a few sparkline rendering styles", "Compare canvas vs svg performance"],
      lastAssistant: "Pushed the comparison results to a gist. SVG was 2× faster for short series; canvas wins above ~1k points.",
      openTool: null,
      diff: { add: 0, del: 0 },
    },
    {
      id: "r6",
      repo: "myorg/web-app",
      branch: "feat/onboarding-v3",
      dirty: 5,
      lastActivity: now - 1000 * 60 * 60 * 24 * 2,
      lastEvent: "permission-pending",
      lastEventLabel: "Wanted to run a migration",
      cwdExists: true,
      prompts: [
        "Wire the new onboarding screens to the auth store",
        "Add analytics events for each step",
        "Run the schema migration against staging",
      ],
      lastAssistant: "I need to run prisma migrate deploy against the staging DB. This will take ~30s and is non-reversible. OK to proceed?",
      openTool: { name: "Bash", args: "prisma migrate deploy" },
      diff: { add: 287, del: 34 },
    },
  ];
}

// Fmt helpers
function fmtRel(ts) {
  const s = Math.floor((Date.now() - ts) / 1000);
  if (s < 5) return "now";
  if (s < 60) return s + "s ago";
  const m = Math.floor(s / 60);
  if (m < 60) return m + "m ago";
  const h = Math.floor(m / 60);
  if (h < 24) return h + "h ago";
  const d = Math.floor(h / 24);
  return d + "d ago";
}

function fmtTokens(n) {
  if (n >= 1000) return (n / 1000).toFixed(n >= 10000 ? 0 : 1) + "k";
  return String(n);
}

function urgencyRank(state) {
  const u = window.URGENCY?.[state];
  return u ? u.rank : 99;
}

window.makeInitialSessions = makeInitialSessions;
window.makeRestoreSessions = makeRestoreSessions;
window.makeSession = makeSession;
window.fmtRel = fmtRel;
window.fmtTokens = fmtTokens;
window.urgencyRank = urgencyRank;
window.STATUS_REASONS = STATUS_REASONS;
