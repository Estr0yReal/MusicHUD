#!/bin/bash
# Renders the HUD to a PNG without needing Screen Recording permission.
#
# This is the reliable way to check the app's appearance: `screencapture`
# silently omits other processes' windows unless it holds Screen Recording
# permission, which makes "the window is missing" look like a rendering bug
# when it is only a permissions artefact.
#
# Usage: scripts/snapshot.sh [output.png]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

OUT="${1:-$PROJECT_ROOT/.build-cache/shots/hud.png}"
mkdir -p "$(dirname "$OUT")"

pkill -f "Music HUD.app/Contents/MacOS/MusicHUD" 2>/dev/null || true

"$SCRIPT_DIR/build-app.sh" release >/dev/null

MUSICHUD_SNAPSHOT="$OUT" "$PROJECT_ROOT/build/Music HUD.app/Contents/MacOS/MusicHUD" 2>&1 | tail -2
