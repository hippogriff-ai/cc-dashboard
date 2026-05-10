// backend/test/staleness.test.ts
import { test, expect } from "bun:test";
import { stalenessDecay } from "../src/claude/classify.ts";

// Verifies zero age yields zero decay.
test("0s → 0 decay", () => expect(stalenessDecay(0)).toBe(0));
// Verifies the 300s grace boundary still yields zero decay.
test("just under grace (300s) → 0 decay", () => expect(stalenessDecay(300)).toBe(0));
// Verifies one second past grace still rounds down to zero decay.
test("301s → 0 decay (rounded)", () => expect(stalenessDecay(301)).toBe(0));
// Verifies one full 360s decay step past the grace window yields one decay unit.
test("660s → 1 decay (300s grace + 360s)", () => expect(stalenessDecay(660)).toBe(1));
// Verifies a one-hour age yields nine decay units.
test("3600s → 9 decay", () => expect(stalenessDecay(3600)).toBe(9));
// Verifies decay caps at 60 for very large ages.
test("36000s → caps at 60", () => expect(stalenessDecay(36_000)).toBe(60));
