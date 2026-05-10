// backend/test/liveness.test.ts
import { test, expect } from "bun:test";
import { isPidAlive, getProcessStartTime } from "../src/util/pid.ts";

// Verifies the process running the test suite is reported alive (basic kill+ps probe).
test("our own pid is alive", () => {
  expect(isPidAlive(process.pid)).toBe(true);
});

// Verifies the ps-based start-time extractor returns a parseable epoch ms for our own pid.
test("getProcessStartTime returns a number for current pid", () => {
  const t = getProcessStartTime(process.pid);
  expect(typeof t).toBe("number");
  expect(t).toBeGreaterThan(0);
});

// Verifies a pid extremely unlikely to exist on macOS is reported dead (ESRCH path).
test("absent pid → false", () => {
  expect(isPidAlive(999_999_999)).toBe(false);
});

// Verifies the start-time-mismatch branch rejects PID reuse (we pass expected=1ms, real start is now-ish).
test("liveness with mismatched start-time → false (PID reuse)", () => {
  // We pass a wildly wrong start time
  expect(isPidAlive(process.pid, 1)).toBe(false);
});

// Verifies passing the actually-observed start time round-trips to true (within 2s tolerance).
test("liveness with matching start-time → true", () => {
  const t = getProcessStartTime(process.pid)!;
  expect(isPidAlive(process.pid, t)).toBe(true);
});
