// backend/test/tail-watch.test.ts
import { test, expect } from "bun:test";
import { mkdtempSync, writeFileSync, appendFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createTail } from "../src/corpus/tail.ts";
import { emptyState } from "../src/corpus/indices.ts";

test("tail picks up new turns appended to a transcript", async () => {
  // verifies: cold-start watch on an empty file, then a single append triggers
  // applyTurns: tokens + file-touch must reflect the appended assistant turn.
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
  // fs.watch on macOS (FSEvents) can delay event delivery under load. Poll up to 2s
  // for the expected state instead of a fixed sleep so the test is robust to jitter.
  const deadline = Date.now() + 2000;
  while (Date.now() < deadline) {
    if (state.bySession.get("sid-1")?.tokens.input === 10) break;
    await new Promise((r) => setTimeout(r, 25));
  }

  const sess = state.bySession.get("sid-1");
  expect(sess?.tokens.input).toBe(10);
  expect(sess?.tokens.output).toBe(5);
  expect(sess?.files.get("/tmp/x.ts")?.edits).toBe(1);
  tail.closeAll();
});

test("cold-start applies pre-existing turns exactly once (no double-count)", () => {
  // verifies Loop 10 deviation 25: cold-start snapshots size first and bounds the read,
  // so an already-populated file is applied exactly once and the offset matches its size.
  const dir = mkdtempSync(join(tmpdir(), "cc-tail-cold-"));
  const file = join(dir, "sess.jsonl");
  const turn = JSON.stringify({
    type: "assistant",
    message: {
      role: "assistant",
      usage: { input_tokens: 7, output_tokens: 3 },
      content: [{ type: "tool_use", name: "Write", input: { file_path: "/tmp/cold.ts" } }],
    },
  }) + "\n";
  writeFileSync(file, turn);

  const state = emptyState();
  const tail = createTail(state);
  tail.add("cold-sid", dir, file);

  expect(state.bySession.get("cold-sid")?.tokens.input).toBe(7);
  expect(state.bySession.get("cold-sid")?.files.get("/tmp/cold.ts")?.edits).toBe(1);
  expect(tail.offsets.get("cold-sid")).toBe(statSync(file).size);
  tail.closeAll();
});
