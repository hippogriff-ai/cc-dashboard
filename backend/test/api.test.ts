// backend/test/api.test.ts
import { test, expect, beforeAll, afterAll } from "bun:test";
import { spawn, type Subprocess } from "bun";

let proc: Subprocess | null = null;
let port = 0;

beforeAll(async () => {
  // Sidecar spawn with isolated CLAUDE_HOME → pristine fixture, no real ~/.claude reads.
  proc = spawn(["bun", "run", "src/server.ts"], {
    env: { ...process.env, CLAUDE_HOME: `${import.meta.dir}/fixtures/dot-claude` },
    stdout: "pipe",
    stderr: "pipe",
  });
  // Read until first newline arrives — the port-announcement JSON line.
  const reader = proc.stdout.getReader();
  const dec = new TextDecoder();
  let buf = "";
  const deadline = Date.now() + 5000;
  while (!buf.includes("\n") && Date.now() < deadline) {
    const { value, done } = await reader.read();
    if (done) break;
    if (value) buf += dec.decode(value);
  }
  reader.releaseLock();
  const line = buf.split("\n")[0] ?? "";
  if (!line.startsWith("{")) throw new Error(`unexpected stdout: ${line.slice(0, 120)}`);
  try {
    port = JSON.parse(line).port;
  } catch (e) {
    throw new Error(`failed to parse port-announcement line: ${line.slice(0, 120)} — ${e instanceof Error ? e.message : String(e)}`);
  }
  if (!Number.isInteger(port) || port <= 0) throw new Error(`invalid port: ${line}`);
});

afterAll(() => {
  proc?.kill("SIGTERM");
});

test("/api/health returns ok=true", async () => {
  // verifies the simplest GET path: the server is up and serializing JSON.
  const r = await fetch(`http://127.0.0.1:${port}/api/health`);
  const j = (await r.json()) as { ok: boolean };
  expect(j.ok).toBe(true);
});

test("/api/live returns sessions array + ide", async () => {
  // verifies live-tab payload shape; CLAUDE_HOME points to the test fixture so the session list will likely be empty but must still be an array (not null).
  const r = await fetch(`http://127.0.0.1:${port}/api/live`);
  const j = (await r.json()) as { sessions: unknown[]; ide: string };
  expect(Array.isArray(j.sessions)).toBe(true);
  expect(typeof j.ide).toBe("string");
});

test("/api/recent returns repos array", async () => {
  // verifies restore-tab payload: ?days=14 should return a repos array regardless of fixture content.
  const r = await fetch(`http://127.0.0.1:${port}/api/recent?days=14`);
  const j = (await r.json()) as { repos: unknown[] };
  expect(Array.isArray(j.repos)).toBe(true);
});

test("/api/decisions requires cwd query param", async () => {
  // verifies the 400 path on missing required query param.
  const r = await fetch(`http://127.0.0.1:${port}/api/decisions`);
  expect(r.status).toBe(400);
});

test("404 on unknown path", async () => {
  // verifies the catch-all 404 for paths the router doesn't match.
  const r = await fetch(`http://127.0.0.1:${port}/api/nope`);
  expect(r.status).toBe(404);
});

test("POST with malformed JSON returns 400 (Loop 12 deviation 36)", async () => {
  // verifies the new explicit 400 path; plan-verbatim swallowed bad JSON into {} and
  // proceeded silently, which made resume/fork run with empty cwd.
  const r = await fetch(`http://127.0.0.1:${port}/api/resume`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: "{not json",
  });
  expect(r.status).toBe(400);
  const j = (await r.json()) as { error: string };
  expect(j.error).toContain("malformed");
});

test("POST /api/resume with empty body returns 400 cwd required (regression)", async () => {
  // verifies that /api/resume now guards against empty cwd (Loop 12 deviation 36 added
  // explicit guards that plan-verbatim skipped on resume/fork).
  const r = await fetch(`http://127.0.0.1:${port}/api/resume`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: "{}",
  });
  expect(r.status).toBe(400);
});

test("/api/projections/__proto__ returns 404 (Loop 12 deviation 38 hasOwn guard)", async () => {
  // verifies the prototype-pollution guard: REGISTRY[__proto__] would otherwise pull
  // Object.prototype off the lookup and crash on .query() with a confusing error.
  const r = await fetch(`http://127.0.0.1:${port}/api/projections/__proto__?cwd=/x`);
  expect(r.status).toBe(404);
});
