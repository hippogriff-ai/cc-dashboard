// backend/test/tokenize.test.ts
import { test, expect } from "bun:test";
import { tokenize } from "../src/ghostty/tokenize.ts";

// Verifies stopwords ("the","is") and short tokens (length < 3) are removed; meaningful words survive.
test("strips stopwords + short tokens", () => {
  const toks = tokenize("the quick fox is on a log");
  expect(toks.has("the")).toBe(false);
  expect(toks.has("is")).toBe(false);
  expect(toks.has("on")).toBe(false);
  expect(toks.has("a")).toBe(false);
  expect(toks.has("quick")).toBe(true);
  expect(toks.has("fox")).toBe(true);
  expect(toks.has("log")).toBe(true);
});

// Verifies %20 and other %-encoded sequences are converted to whitespace separators before lowercasing.
test("strips %-encoding", () => {
  const toks = tokenize("foo%20bar%2Fbaz");
  expect(toks.has("foo")).toBe(true);
  expect(toks.has("bar")).toBe(true);
  expect(toks.has("baz")).toBe(true);
});

// Verifies NFKD normalization removes diacritics so "café" becomes "cafe".
test("normalizes unicode", () => {
  const toks = tokenize("café résumé");
  expect(toks.has("cafe")).toBe(true);
  expect(toks.has("resume")).toBe(true);
});

// Verifies tokens consisting only of digits are filtered (e.g. "123" excluded, "abc123" kept).
test("rejects pure-numeric tokens", () => {
  const toks = tokenize("123 456 abc123 hello");
  expect(toks.has("123")).toBe(false);
  expect(toks.has("456")).toBe(false);
  expect(toks.has("abc123")).toBe(true);
  expect(toks.has("hello")).toBe(true);
});
