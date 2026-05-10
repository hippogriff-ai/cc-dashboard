// backend/test/pid.test.ts
import { test, expect } from "bun:test";
import { isPidAlive } from "../src/util/pid.ts";

// Verifies the current process PID is reported alive (kill(pid, 0) signal-0 probe).
test("isPidAlive returns true for the current process", () => {
  expect(isPidAlive(process.pid)).toBe(true);
});

// Verifies a PID extremely unlikely to exist returns false (catch path of the probe).
test("isPidAlive returns false for a nonexistent pid", () => {
  expect(isPidAlive(99999999)).toBe(false);
});
