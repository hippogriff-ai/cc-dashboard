// backend/test/classify.test.ts
import { test, expect } from "bun:test";
import { classify } from "../src/claude/classify.ts";
import { readJsonlTail } from "../src/claude/transcript.ts";

const root = "test/fixtures/dot-claude/projects/-tmp-test-repo";

// Verifies an empty transcript classifies to CLEAR.
test("empty transcript → CLEAR", () => {
  const r = classify([], true);
  expect(r.event).toBe("CLEAR");
});

// Verifies an assistant turn ending with a permission-style question maps to PERMISSION_PENDING with high priority.
test("assistant ending with permission phrasing → PERMISSION_PENDING", () => {
  const r = classify(readJsonlTail(`${root}/sess-permission.jsonl`, 100), true);
  expect(r.event).toBe("PERMISSION_PENDING");
  expect(r.priority).toBeLessThanOrEqual(15);
});

// Verifies a user tool_result with is_error as the last turn maps to TOOL_FAILED with the error detail in reason.
test("user tool_result is_error last → TOOL_FAILED", () => {
  const r = classify(readJsonlTail(`${root}/sess-toolfailed.jsonl`, 100), true);
  expect(r.event).toBe("TOOL_FAILED");
  expect(r.reason).toContain("pytest");
});

// Verifies an assistant text turn ending with '?' (non-permission) maps to ASK.
test("assistant text ending with '?' → ASK", () => {
  const r = classify(readJsonlTail(`${root}/sess-ask.jsonl`, 100), true);
  expect(r.event).toBe("ASK");
});

// Verifies an assistant turn with an open tool_use while alive maps to WORKING and surfaces the open tool name.
test("assistant with open tool_use + alive → WORKING", () => {
  const r = classify(readJsonlTail(`${root}/sess-working.jsonl`, 100), true);
  expect(r.event).toBe("WORKING");
  expect(r.open_tool?.name).toBe("Bash");
});

// Verifies an assistant text turn that does not end with '?' and has no tool maps to IDLE_AFTER_COMPLETE.
test("assistant text not ending with '?' and no tool → IDLE_AFTER_COMPLETE", () => {
  const r = classify(readJsonlTail(`${root}/sess-idle.jsonl`, 100), true);
  expect(r.event).toBe("IDLE_AFTER_COMPLETE");
});

// Verifies dead session with an open tool_use clears open_tool (no stale tool name on a dead row).
test("assistant with open tool_use + dead → IDLE_AFTER_COMPLETE, open_tool null", () => {
  const r = classify(readJsonlTail(`${root}/sess-working.jsonl`, 100), false);
  expect(r.event).toBe("IDLE_AFTER_COMPLETE");
  expect(r.open_tool).toBeNull();
});

// Verifies image-only error tool_result produces a marker reason instead of a misleadingly empty error string.
test("tool_result is_error with image-only content → TOOL_FAILED with marker", () => {
  const transcript = [
    { type: "assistant", message: { role: "assistant", content: [{ type: "tool_use", name: "Read", id: "x1" }] } },
    {
      type: "user",
      message: {
        role: "user",
        content: [
          {
            type: "tool_result",
            tool_use_id: "x1",
            is_error: true,
            content: [{ type: "image", source: { type: "base64", media_type: "image/png", data: "iVBOR..." } }],
          },
        ],
      },
    },
  ];
  const r = classify(transcript, true);
  expect(r.event).toBe("TOOL_FAILED");
  expect(r.reason).toContain("no text in error result");
});

// Verifies prose like "okay to revert" without a first-person verb does NOT trigger PERMISSION_PENDING (regex tightened).
test("assistant prose with 'okay to revert' but no first-person verb → ASK, not PERMISSION_PENDING", () => {
  const transcript = [
    { type: "user", message: { role: "user", content: "what next" } },
    {
      type: "assistant",
      message: {
        role: "assistant",
        content: [{ type: "text", text: "It would be okay to revert if needed, but should we try the patch first?" }],
      },
    },
  ];
  const r = classify(transcript, true);
  expect(r.event).toBe("ASK");
  expect(r.priority).toBeGreaterThan(15);
});
