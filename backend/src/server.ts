// backend/src/server.ts
import { existsSync } from "node:fs";
import { log } from "./util/log.ts";
import { loadLiveSessions } from "./claude/sessions.ts";
import { loadRecentByRepo } from "./claude/recent.ts";
import { buildPanel } from "./claude/panel.ts";
import { buildSessionDetail } from "./claude/sessionDetail.ts";
import { findTranscript, readJsonlTail } from "./claude/transcript.ts";
import { classify } from "./claude/classify.ts";
import { focusGhostty } from "./ghostty/focus.ts";
import { resumeCommand } from "./actions/resume.ts";
import { forkSummary } from "./actions/fork.ts";
import { openInIde } from "./actions/openIde.ts";
import { detectIde } from "./util/ide.ts";
import { emptyState } from "./corpus/indices.ts";
import { createTail } from "./corpus/tail.ts";
import { decisionsProjection, REGISTRY } from "./corpus/projections.ts";

// --- arg parsing + port validation -------------------------------------------------
const args = process.argv.slice(2);
const portIdx = args.indexOf("--port");
const rawPort = portIdx >= 0 ? args[portIdx + 1] : undefined;

const port = ((): number => {
  if (rawPort === undefined) return 0; // "any free port" — Swift parses the JSON announcement.
  const n = Number(rawPort);
  if (!Number.isInteger(n) || n < 0 || n > 65535) {
    log.error("invalid --port value", { raw: rawPort });
    process.exit(2);
  }
  return n;
})();

// --- crash handlers (Loop 1 hardening, preserved) ---------------------------------
let shuttingDown = false;
process.on("uncaughtException", (e: Error): void => {
  if (shuttingDown) return; // already on the SIGTERM path; don't override its exit 0.
  log.error("uncaught exception", { message: e.message, stack: e.stack });
  process.exit(1);
});
process.on("unhandledRejection", (reason: unknown): void => {
  if (shuttingDown) return;
  log.error("unhandled rejection", { reason: reason instanceof Error ? reason.message : String(reason) });
  process.exit(1);
});

// --- corpus state + tail --------------------------------------------------------
const state = emptyState();
const tail = createTail(state);

function rebalanceWatchers(): void {
  // Wrapped because loadLiveSessions / findTranscript are sync FS reads that can throw
  // on EACCES / EMFILE / ENOENT-race. An unguarded throw at module-load time would
  // crash before the JSON port announcement, leaving the Swift parent hung waiting on
  // stdout. Inside setInterval, an unguarded throw becomes uncaughtException → exit 1
  // → silent dashboard death mid-session. Catch and keep the process alive.
  try {
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
  } catch (e) {
    log.error("rebalanceWatchers failed; will retry on next tick", {
      error: e instanceof Error ? e.message : String(e),
      stack: e instanceof Error ? e.stack : undefined,
    });
  }
}
rebalanceWatchers();
const rebalanceInterval = setInterval(rebalanceWatchers, 5000);
rebalanceInterval.unref?.();

// --- HTTP helpers ------------------------------------------------------------------
function ok(body: unknown): Response { return Response.json(body); }
function err(status: number, msg: string): Response { return Response.json({ error: msg }, { status }); }
function asString(v: unknown): string { return typeof v === "string" ? v : ""; }
function asStringOrNull(v: unknown): string | null { return typeof v === "string" && v.length > 0 ? v : null; }

// --- Bun.serve (preserves Loop 1 try/catch + error callback) ----------------------
let server: ReturnType<typeof Bun.serve>;
try {
  server = Bun.serve({
    hostname: "127.0.0.1",
    port,
    async fetch(req: Request): Promise<Response> {
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
            const days = Number.parseInt(q.get("days") ?? "14", 10);
            const ide = detectIde().display;
            const repos = await loadRecentByRepo(Number.isFinite(days) && days > 0 ? days : 14);
            return ok({ repos, ide, ts: Date.now() / 1000 });
          }
          if (p === "/api/panel") {
            const cwd = q.get("cwd") ?? "";
            const sid = q.get("sid") || null;
            if (!cwd) return err(400, "cwd required");
            const alive = sid !== null && tail.watchers.has(sid);
            return ok(await buildPanel(cwd, sid, alive));
          }
          if (p === "/api/decisions") {
            const cwd = q.get("cwd") ?? "";
            if (!cwd) return err(400, "cwd required");
            // Defensive copy: same rationale as buildSessionDetail (Loop 11 deviation 32) —
            // never expose the live state.decisionsByCwd reference; tail.ts mutates it.
            return ok({ decisions: [...decisionsProjection.query(state, cwd)] });
          }
          if (p === "/api/session-detail") {
            const sid = q.get("sid") ?? "";
            if (!sid) return err(400, "sid required");
            const detail = buildSessionDetail(state, sid);
            if (!detail) return err(404, "session not in index");
            // Post-classify: overwrite the placeholder last_assistant / open_tool.
            const tp = findTranscript(detail.cwd, detail.sessionId);
            if (tp) {
              const turns = readJsonlTail(tp, 400);
              const meta = classify(turns, tail.watchers.has(detail.sessionId));
              detail.last_assistant = meta.last_assistant;
              detail.open_tool = meta.open_tool;
            }
            return ok(detail);
          }
          if (p.startsWith("/api/projections/")) {
            const name = p.replace("/api/projections/", "");
            // hasOwn guard so a `name` of `__proto__` / `constructor` / `toString`
            // can't pull a truthy value off Object.prototype and crash on .query().
            if (!Object.prototype.hasOwnProperty.call(REGISTRY, name)) return err(404, "unknown projection");
            const proj = REGISTRY[name];
            if (!proj) return err(404, "unknown projection");
            const cwd = q.get("cwd") ?? "";
            if (!cwd) return err(400, "cwd required");
            return ok({ name, value: proj.query(state, cwd) });
          }
          return err(404, "not found");
        }
        if (req.method === "POST") {
          // Distinguish "no body" / "empty body" (treat as {}) from "malformed JSON"
          // (return 400 with a clear message). Plan-verbatim swallowed both into {},
          // which made resume/fork silently invoke with empty cwd.
          let body: Record<string, unknown> = {};
          const raw = await req.text();
          if (raw.trim().length > 0) {
            try {
              const parsed: unknown = JSON.parse(raw);
              if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
                body = parsed as Record<string, unknown>;
              } else {
                return err(400, "body must be a JSON object");
              }
            } catch {
              return err(400, "malformed JSON body");
            }
          }
          if (p === "/api/focus") {
            const cwd = asString(body.cwd);
            const sid = asStringOrNull(body.sid);
            if (!cwd) return err(400, "cwd required");
            return ok(await focusGhostty(cwd, sid));
          }
          if (p === "/api/resume") {
            const cwd = asString(body.cwd);
            if (!cwd) return err(400, "cwd required");
            return ok(resumeCommand(cwd, asStringOrNull(body.sid)));
          }
          if (p === "/api/fork") {
            const cwd = asString(body.cwd);
            if (!cwd) return err(400, "cwd required");
            return ok(await forkSummary(cwd, asStringOrNull(body.sid)));
          }
          if (p === "/api/open-ide") {
            const cwd = asString(body.cwd);
            if (!cwd) return err(400, "cwd required");
            return ok(openInIde(cwd));
          }
          if (p === "/api/shutdown") {
            setTimeout(() => process.exit(0), 50).unref?.();
            return ok({ ok: true });
          }
          return err(404, "not found");
        }
        return err(405, "method not allowed");
      } catch (e) {
        log.error("handler exception", { path: p, error: e instanceof Error ? e.message : String(e), stack: e instanceof Error ? e.stack : undefined });
        return err(500, "internal error");
      }
    },
    error(e: Error): Response {
      log.error("request failed (Bun.serve)", { message: e.message, stack: e.stack });
      return err(500, "internal error");
    },
  });
} catch (raw) {
  const e = raw as NodeJS.ErrnoException;
  log.error("backend failed to start", { port, code: e.code, message: e.message });
  process.exit(1);
}

// First stdout line is JSON port announcement — Swift parent parses this.
console.log(JSON.stringify({ port: server.port }));
log.info("backend ready", { port: server.port });

process.on("SIGTERM", (): void => {
  if (shuttingDown) return;
  shuttingDown = true;
  log.info("SIGTERM");
  try {
    tail.closeAll();
  } catch (e) {
    log.warn("tail.closeAll failed during SIGTERM", {
      error: e instanceof Error ? e.message : String(e),
    });
  }
  process.exit(0);
});

// Parent-death detection. Two mechanisms in defence-in-depth order; either
// one firing is enough.
//
// 1. Stdin EOF (preferred). The Swift parent assigns a Pipe to our stdin and
//    never writes to it; it holds the write-end alive for its own lifetime.
//    When the parent dies by any cause — graceful Cmd-Q, SIGKILL, OOM,
//    crash — the kernel closes its FDs and our stdin gets EOF. Fires
//    immediately, no polling, no event-loop dependency. Gated on the
//    explicit CC_DASHBOARD_PARENT_PIPE env var that the Swift parent sets
//    to declare the contract — required because other spawn paths (`bun
//    test`, `bun run`, manual `bun src/server.ts`) leave stdin as
//    /dev/null or a TTY, both of which would mis-fire the watchdog (the
//    former EOFs immediately, killing the server before tests connect;
//    the latter EOFs on Ctrl-D, killing dev sessions on accidental keys).
//    The env-var contract makes the dependency explicit instead of
//    heuristic.
// 2. Ppid poll (fallback). On macOS the kernel reparents orphans to launchd
//    (PID 1), so a `getppid()` change is a reliable death signal. Catches
//    the rare case where stdin is closed by the parent for an unrelated
//    reason but the parent itself is still alive — shouldn't happen given
//    our pipe contract, but kept as belt-and-suspenders. Without either
//    watchdog, prior `make test-app` runs leak ~10 stranded sidecars apiece
//    — confirmed via `pgrep` in Loop 33, then re-confirmed in Loop 50 when
//    52 zombies (Tue 2026-05-05 onward) were found alive at once because
//    earlier builds shipped without the watchdog.
function exitOnParentDeath(trigger: string, extra?: Record<string, unknown>): void {
  if (shuttingDown) return;
  shuttingDown = true;
  log.info("parent process died; exiting", { trigger, ...(extra ?? {}) });
  try {
    tail.closeAll();
  } catch {
    // Already shutting down — best-effort cleanup, no log spam.
  }
  process.exit(0);
}

if (process.env.CC_DASHBOARD_PARENT_PIPE === "1") {
  process.stdin.on("end", (): void => exitOnParentDeath("stdin EOF"));
  process.stdin.on("close", (): void => exitOnParentDeath("stdin close"));
  // Without resume() the stream stays paused and 'end' / 'close' never fire.
  process.stdin.resume();
}

const initialPpid: number = process.ppid;
setInterval((): void => {
  if (shuttingDown) return;
  if (process.ppid !== initialPpid) {
    exitOnParentDeath("ppid change", { initial: initialPpid, current: process.ppid });
  }
}, 2000).unref?.();
