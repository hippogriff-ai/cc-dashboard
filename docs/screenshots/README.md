# Screenshots

These are the images embedded in the top-level `README.md`. They're rendered
from the JSX design prototypes in `docs/ux-design/` (not from a live app) via
a headless browser, so they don't drift with real-user data and don't depend
on macOS permissions or signing state.

## Refreshing them

```bash
npx playwright install chromium     # one-time
node scripts/capture-screenshots.mjs
```

The script spins up a tiny HTTP server, navigates a headless Chromium to
`_render.html?tab=…` five times, and writes each PNG into this directory.
`_render.html` is a small wrapper that loads `../ux-design/{icons,data,
components,screens}.jsx` and re-implements just the `LivePopover` shell from
`../ux-design/app.jsx`.

> `docs/ux-design/` is gitignored — refreshing therefore requires a local
> checkout of the design source that lives outside this repo.

## Shot list

| File | What it shows |
|---|---|
| `01-live.png` | Live tab — ranked inbox of running sessions. |
| `02-restore.png` | Restore tab — recent projects, even ones you closed. |
| `03-detail.png` | Session detail view — tokens, files, decisions, branch history. |
| `04-navigate.png` | Navigate-mode overlay — `1`–`9` jump labels on rows. |
| `05-settings.png` | Settings — theme, hotkeys, quiet mode. |
