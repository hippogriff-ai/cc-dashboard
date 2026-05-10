#!/bin/bash
# Capture the screenshots referenced in the top-level README.
#
# Usage (from repo root):
#   ./scripts/capture-screenshots.sh
#
# For each shot, follow the instruction, then click on the popover when the
# screencapture cursor appears (it captures the window you click on).

set -e
cd "$(dirname "$0")/.."
mkdir -p docs/screenshots

shoot() {
    local name="$1"
    local instruction="$2"
    echo
    echo "─── $name ───"
    echo "    $instruction"
    echo "    Then press Enter; click on the popover when the cursor changes."
    read -r -p "    [Enter] when ready: "
    /usr/sbin/screencapture -W "docs/screenshots/$name.png"
    echo "    ✓ saved → docs/screenshots/$name.png"
}

echo "Capturing 5 screenshots for README. Open cc-dashboard before each shot."

shoot "01-live"     "Click the cc-dashboard menubar icon. Make sure the Live tab is showing your sessions."
shoot "02-restore"  "Switch to the Restore tab (Tab key, or click)."
shoot "03-detail"   "On Live, click a session row's chevron (or tap row) to open Session Detail."
shoot "04-navigate" "On Live, press your navigate-mode hotkey (or 'n') so the 1–9 overlay numbers appear."
shoot "05-settings" "Switch to Settings tab."

echo
echo "Done. Review the PNGs, then commit with:"
echo "  git add docs/screenshots/"
