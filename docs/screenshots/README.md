# Screenshots

These are the images embedded in the top-level `README.md`.

## Capturing / refreshing them

```bash
./scripts/capture-screenshots.sh
```

The script walks you through 5 shots interactively. For each one, follow the
instruction, hit Enter, and click on the popover when `screencapture`'s cursor
appears.

## Shot list

| File | What it shows |
|---|---|
| `01-live.png` | Live tab — ranked inbox of running sessions. |
| `02-restore.png` | Restore tab — recent projects, even ones you closed. |
| `03-detail.png` | Session detail view — tokens, files, decisions, branch history. |
| `04-navigate.png` | Navigate-mode overlay — `1`–`9` jump labels on rows. |
| `05-settings.png` | Settings — theme, hotkeys, quiet mode. |

Keep dimensions consistent (the popover is fixed-width). Crop tightly to the
popover; don't include desktop background or other windows.
