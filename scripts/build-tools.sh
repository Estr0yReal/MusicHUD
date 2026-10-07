#!/bin/bash
#
# Builds the Phase 3 diagnostic tools as real .app bundles.
#
# WHY A BUNDLE IS REQUIRED
# Core Audio process taps need `kTCCServiceAudioCapture` ("System Audio
# Recording"). A bare Mach-O launched from a shell has no bundle identity, so
# macOS attributes the request to the *responsible* process — typically the
# terminal — and the permission prompt is raised for that app instead. A bundle
# gives the tool its own identity, which is both correct and the only way the
# prompt can be answered for it.
#
# The Info.plist key is `NSAudioCaptureUsageDescription`, confirmed by the
# string table in tccd. It is *not* NSMicrophoneUsageDescription and *not*
# Screen Recording.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

SDK="$(xcrun --show-sdk-path --sdk macosx)"
OUT_DIR="$PROJECT_ROOT/build"

build_tool() {
    local name="$1"
    local source="$2"
    local bundle="$OUT_DIR/${name}.app"

    echo "▸ Building ${name}..."
    swiftc -O -sdk "$SDK" \
        -framework CoreAudio -framework AppKit -framework Foundation \
        "$source" -o "$OUT_DIR/${name}"

    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS"
    cp "$OUT_DIR/$name" "$bundle/Contents/MacOS/${name}"

    cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$name</string>
    <key>CFBundleIdentifier</key><string>com.musichud.diagnostics.$name</string>
    <key>CFBundleName</key><string>$name</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.3.0</string>
    <key>LSMinimumSystemVersion</key><string>14.2</string>
    <!-- Required for kTCCServiceAudioCapture ("System Audio Recording"). -->
    <key>NSAudioCaptureUsageDescription</key>
    <string>Music HUD 需要采集系统音频输出，以绘制实时频谱。</string>
</dict>
</plist>
PLIST

    codesign --force --sign - --timestamp=none "$bundle" >/dev/null 2>&1 || true
    echo "  ✓ $bundle"
}

build_tool "AudioCaptureProbe" "$PROJECT_ROOT/tools/AudioCaptureProbe.swift"

echo
echo "Run it with:"
echo "  open -a \"$OUT_DIR/AudioCaptureProbe.app\" --args --seconds 20 --log /tmp/probe.log"

# Phase 6.2: validates the window-drag coordinate model against a real NSWindow
# and real pointer positions. Uses the same WindowDragMath the app uses.
swiftc -O -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -framework AppKit -framework CoreGraphics \
  tools/DragProbe.swift Sources/MusicHUDCore/Interaction/WindowDragMath.swift \
  -o build/DragProbe
echo "  ✓ build/DragProbe"
