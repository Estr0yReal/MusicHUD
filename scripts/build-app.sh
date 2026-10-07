#!/bin/bash
#
# Builds Music HUD and assembles a launchable macOS .app bundle.
#
# SwiftPM produces a bare Mach-O executable. A GUI app needs a bundle so the
# window server gives it a proper identity, so this script wraps the binary in
# the minimal bundle structure a HUD needs, then ad-hoc signs it.
#
# Usage:
#   scripts/build-app.sh [debug|release]
#
# Output:
#   build/Music HUD.app

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$SCRIPT_DIR/env.sh"

CONFIGURATION="${1:-release}"
APP_NAME="Music HUD"
BUNDLE_DIR="$PROJECT_ROOT/build/$APP_NAME.app"

echo "▸ Building MusicHUD ($CONFIGURATION)…"
swift build "${SWIFT_FLAGS[@]}" -c "$CONFIGURATION" --product MusicHUD

BIN_PATH="$(swift build "${SWIFT_FLAGS[@]}" -c "$CONFIGURATION" --show-bin-path)"

echo "▸ Assembling bundle…"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

# Localisations: SwiftUI resolves `Text("key")` against Bundle.main for the
# locale in the environment, and Bundle.main's resource path is
# Contents/Resources — so the .lproj directories have to live here, not inside
# SwiftPM's resource bundle.
RESOURCE_BUNDLE="$BIN_PATH/MusicHUD_MusicHUD.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    for lproj in "$RESOURCE_BUNDLE"/*.lproj; do
        [ -d "$lproj" ] || continue
        cp -R "$lproj" "$BUNDLE_DIR/Contents/Resources/"
    done
    echo "  localisations: $(ls -d "$BUNDLE_DIR/Contents/Resources"/*.lproj 2>/dev/null | wc -l | tr -d ' ')"
else
    echo "  warning: no resource bundle found — localisation will fall back to keys" >&2
fi

cp "$BIN_PATH/MusicHUD" "$BUNDLE_DIR/Contents/MacOS/MusicHUD"

cat > "$BUNDLE_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>MusicHUD</string>
    <key>CFBundleIdentifier</key>
    <string>com.musichud.desktophud</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Music HUD</string>
    <key>CFBundleDisplayName</key>
    <string>Music HUD</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>7</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>

    <!-- Accessory app: no Dock icon, no app switcher entry. The HUD is a
         desktop component; the status-bar menu is the way back in. -->
    <key>LSUIElement</key>
    <true/>

    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>

    <!-- Phase 2 reads Music.app state over public Apple Events. The wording
         states exactly what is read and what is sent, and deliberately does not
         claim access to the user's library, because the code never modifies
         anything in it. -->
    <key>NSAppleEventsUsageDescription</key>
    <string>Music HUD 需要访问「音乐」App，以读取当前播放的歌曲名称、艺术家、专辑、专辑封面、播放状态与播放进度，并发送上一首、播放/暂停、下一首指令。不会读取或修改您的音乐资料库内容。</string>

    <!-- Phase 3 captures system audio with a Core Audio process tap.
         That is gated by kTCCServiceAudioCapture ("System Audio Recording"),
         whose Info.plist key is NSAudioCaptureUsageDescription — confirmed
         against tccd's own string table, not guessed.

         It is NOT the microphone permission and NOT Screen Recording: a process
         tap needs neither. NSMicrophoneUsageDescription is deliberately absent
         because nothing in this app records from an input device. -->
    <key>NSAudioCaptureUsageDescription</key>
    <string>Music HUD 需要采集系统音频输出，以绘制实时频谱。仅用于分析音频波形，不会录制或保存音频内容。</string>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc signing…"
# Ad-hoc signature (-) is enough for local use. A distributed build would use a
# Developer ID identity plus notarisation.
codesign --force --sign - --timestamp=none "$BUNDLE_DIR" >/dev/null 2>&1 \
    || echo "  (codesign skipped — unsigned bundle still runs locally)"

echo "✓ Built $BUNDLE_DIR"
echo
echo "Run it with:"
echo "  open \"$BUNDLE_DIR\""
