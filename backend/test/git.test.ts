// backend/test/git.test.ts
import { test, expect, beforeEach } from "bun:test";
import { gitInfo, gitInfoAsync, _clearGitInfoCache } from "../src/util/git.ts";

// Each test gets a clean cache so TTL-based assertions are deterministic.
beforeEach(() => { _clearGitInfoCache(); });

// Verifies gitInfo against the cc-dashboard repo itself: branch is string-or-null,
// dirty is a non-negative integer, last_commit is null or starts with a hex prefix.
test("gitInfo against the cc-dashboard repo returns sane shape", () => {
  const info = gitInfo(process.cwd());
  // branch: non-empty string OR null (must not throw)
  if (info.branch !== null) {
    expect(typeof info.branch).toBe("string");
    expect(info.branch.length).toBeGreaterThan(0);
  }
  // dirty: non-negative integer
  expect(Number.isInteger(info.dirty)).toBe(true);
  expect(info.dirty).toBeGreaterThanOrEqual(0);
  // last_commit: null or string starting with a hex short-hash prefix
  if (info.last_commit !== null) {
    expect(typeof info.last_commit).toBe("string");
    expect(info.last_commit).toMatch(/^[0-9a-f]+\s/);
  }
});

// Verifies that calling gitInfo on a non-existent / non-repo path returns null
// branch + last_commit and a 0 dirty count, without throwing.
test("gitInfo returns null fields for non-repo path", () => {
  const info = gitInfo("/tmp/definitely-not-a-git-repo-xyz123");
  expect(info.branch).toBeNull();
  expect(info.last_commit).toBeNull();
  expect(info.dirty).toBe(0);
});

// Verifies the async variant returns the same shape as the sync one.
// Equivalence is checked across both the cc-dashboard repo (real git) and a
// non-repo path (the null-fields fallback) so the parser used by both code
// paths is exercised.
test("gitInfoAsync returns the same shape as gitInfo for repo and non-repo", async () => {
  _clearGitInfoCache();
  const syncRepo = gitInfo(process.cwd());
  _clearGitInfoCache();
  const asyncRepo = await gitInfoAsync(process.cwd());
  // dirty count may legitimately differ across two probes if the working tree
  // changed between them; branch/last_commit format must match.
  expect(asyncRepo.branch).toBe(syncRepo.branch);
  if (syncRepo.last_commit !== null && asyncRepo.last_commit !== null) {
    expect(asyncRepo.last_commit.split(" ")[0]).toBe(syncRepo.last_commit.split(" ")[0]);
  }

  _clearGitInfoCache();
  const asyncNon = await gitInfoAsync("/tmp/definitely-not-a-git-repo-xyz999");
  expect(asyncNon.branch).toBeNull();
  expect(asyncNon.last_commit).toBeNull();
  expect(asyncNon.dirty).toBe(0);
});

// Verifies the 5s TTL cache returns the SAME object reference within the
// window without re-probing — proving we won't re-spawn three subprocesses
// per cwd on every poll cycle. Reference equality is the cheapest invariant
// that distinguishes a cache hit from a fresh probe.
test("gitInfo cache returns the same object reference within 5s TTL", () => {
  _clearGitInfoCache();
  const a = gitInfo(process.cwd());
  const b = gitInfo(process.cwd());
  expect(b).toBe(a); // reference equality => served from cache
});

// Same invariant for the async path, plus that async/sync share the cache:
// an initial sync call must satisfy a subsequent async call from cache.
test("gitInfoAsync cache hit serves from the same store as gitInfo", async () => {
  _clearGitInfoCache();
  const a = gitInfo(process.cwd());
  const b = await gitInfoAsync(process.cwd());
  expect(b).toBe(a);
});
