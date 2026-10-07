#!/bin/bash
#
# Phase 4.5 audit harness.
#
# Measures the running app's CPU in a controlled scenario. Written because
# `ps -o %cpu` reports a lifetime average, not an instantaneous figure, and
# comparing scenarios with it produced numbers that did not reproduce.
#
# Usage:  scripts/audit-measure.sh <scenario> [duration]
#
#   A   HUD hidden, audio pipeline running
#   B   HUD hidden, audio pipeline stopped
#   C   HUD + spectrum at 20 FPS
#   D   HUD + spectrum at 30 FPS
#   E   HUD + spectrum at 60 FPS
#   F   HUD + spectrum, music paused (no new frames)
#
# The scenario is applied through the app's own persisted settings, so no
# audit-only code path is needed for the frame-rate cases.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SCENARIO="${1:-D}"
DURATION="${2:-20}"
APP="$PROJECT_ROOT/build/Music HUD.app"
BUNDLE_ID="com.musichud.desktophud"
PLIST="$HOME/Library/Preferences/$BUNDLE_ID.plist"

set_setting() {
    python3 - "$PLIST" "$1" "$2" <<'PY'
import json, plistlib, sys
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
data = plistlib.load(open(path, 'rb'))
settings = json.loads(data["MusicHUD.settings.v1"].decode())
if value == "true":   parsed = True
elif value == "false": parsed = False
elif value.lstrip('-').isdigit(): parsed = int(value)
else: parsed = value
settings[key] = parsed
data["MusicHUD.settings.v1"] = json.dumps(settings, separators=(',', ':')).encode()
plistlib.dump(data, open(path, 'wb'))
PY
}

stop_app() {
    pkill -f "Music HUD.app/Contents/MacOS/MusicHUD" 2>/dev/null || true
    sleep 1
}

start_app() {
    open -a "$APP" --env MUSICHUD_AUDIO_LOG="$PROJECT_ROOT/.build-cache/audit-$SCENARIO.log"
}

# --- Apply the scenario ---------------------------------------------------
stop_app

case "$SCENARIO" in
  A) set_setting showOnLaunch false; set_setting spectrumFrameRate 30 ;;
  B) set_setting showOnLaunch false; set_setting spectrumFrameRate 30 ;;
  C) set_setting showOnLaunch true;  set_setting spectrumFrameRate 20 ;;
  D) set_setting showOnLaunch true;  set_setting spectrumFrameRate 30 ;;
  E) set_setting showOnLaunch true;  set_setting spectrumFrameRate 60 ;;
  F) set_setting showOnLaunch true;  set_setting spectrumFrameRate 30 ;;
  *) echo "unknown scenario $SCENARIO"; exit 2 ;;
esac
# `defaults` caches; make sure cfprefsd picks the change up before launch.
defaults read "$BUNDLE_ID" >/dev/null 2>&1 || true

# Music must actually be playing, otherwise the tap start blocks on coreaudiod
# waiting for writers and the measurement never reaches steady state.
if ! pgrep -x Music >/dev/null; then open -a Music; sleep 5; fi
osascript -e 'tell application "Music" to play' >/dev/null 2>&1 || true
sleep 3

start_app
sleep 10

PID="$(pgrep -f "Music HUD.app/Contents/MacOS/MusicHUD" | head -1)"
if [ -z "$PID" ]; then echo "app did not start"; exit 3; fi

if [ "$SCENARIO" = "F" ]; then
    osascript -e 'tell application "Music" to pause' >/dev/null 2>&1 || true
    sleep 3
fi

# --- Measure --------------------------------------------------------------
"$SCRIPT_DIR/cpu-sample.py" "$PID" 2 "$((DURATION / 2))"

echo "  RSS    $(ps -o rss= -p "$PID" | awk '{printf "%.1f MB", $1/1024}')"
echo "  log    $PROJECT_ROOT/.build-cache/audit-$SCENARIO.log"
