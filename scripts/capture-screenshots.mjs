// Capture the README screenshots by headless-rendering the JSX prototypes
// in `docs/ux-design/` (gitignored — only the project owner has them).
//
// Usage:
//   npx playwright install chromium     # one-time, ~150 MB
//   node scripts/capture-screenshots.mjs
//
// Output:
//   docs/screenshots/0[1-5]-*.png
//
// Renders `docs/screenshots/_render.html` (loads icons/data/components/screens
// from ../ux-design/), driven by `?tab=…&detail=1&nav=1` query strings. Serves
// the repo over a local HTTP port because file:// won't resolve the
// sibling-directory script srcs reliably.

import { chromium } from "playwright";
import { createServer } from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { join, extname, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..");

if (!existsSync(join(repoRoot, "docs/ux-design/styles.css"))) {
  console.error(
    "docs/ux-design/ is missing — re-rendering needs the JSX design source.\n" +
    "The PNGs in docs/screenshots/ are what ships; this script is only for\n" +
    "refreshing them. Restore docs/ux-design/ from your local backup."
  );
  process.exit(1);
}

const MIME = {
  ".html": "text/html",
  ".css": "text/css",
  ".js": "application/javascript",
  ".jsx": "application/javascript",
  ".png": "image/png",
  ".svg": "image/svg+xml",
};

const server = createServer((req, res) => {
  const p = decodeURIComponent(new URL(req.url, "http://x").pathname);
  const fp = join(repoRoot, p);
  if (!fp.startsWith(repoRoot) || !existsSync(fp)) {
    res.writeHead(404).end("not found");
    return;
  }
  res.writeHead(200, { "Content-Type": MIME[extname(fp)] ?? "text/plain" });
  res.end(readFileSync(fp));
});

await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;
const base = `http://127.0.0.1:${port}/docs/screenshots/_render.html`;

const shots = [
  { name: "01-live",     query: "?tab=Live",            size: { width: 600, height: 700 } },
  { name: "02-restore",  query: "?tab=Restore",         size: { width: 600, height: 700 } },
  { name: "03-detail",   query: "?tab=Live&detail=1",   size: { width: 600, height: 760 } },
  { name: "04-navigate", query: "?tab=Live&nav=1",      size: { width: 600, height: 700 } },
  { name: "05-settings", query: "?tab=Settings",        size: { width: 600, height: 700 } },
];

const browser = await chromium.launch();
try {
  for (const { name, query, size } of shots) {
    const ctx = await browser.newContext({ viewport: size, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    await page.goto(base + query, { waitUntil: "load" });
    // Babel-standalone transforms <script type="text/babel"> async after
    // 'load'. The render entry point sets window.__rendered when its render
    // call returns; wait on it instead of a fixed sleep.
    await page.waitForFunction(() => window.__rendered === true, null, { timeout: 5000 });
    // Extra settle for fonts / SVG icons that come in after the React render.
    await page.waitForTimeout(500);
    const out = join(repoRoot, "docs/screenshots", `${name}.png`);
    await page.screenshot({ path: out, type: "png" });
    console.log(`✓ ${name}.png`);
    await ctx.close();
  }
} finally {
  await browser.close();
  server.close();
}
