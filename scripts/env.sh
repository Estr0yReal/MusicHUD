#!/bin/bash
# Shared build environment for Music HUD.
#
# Why this exists: SwiftPM and Clang want to write their caches to
# ~/Library/org.swift.swiftpm and ~/Library/Caches, and the Clang module cache
# to a directory under /var/folders. In a sandboxed or restricted shell those
# paths are not writable, which makes even manifest parsing fail. Redirecting
# them into the workspace keeps builds self-contained and reproducible.
#
# --disable-sandbox is also required: SwiftPM wraps manifest compilation in its
# own `sandbox-exec`, and nesting that inside an outer sandbox fails with
# "sandbox_apply: Operation not permitted".

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT

export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build-cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build-cache/swiftpm"
export TMPDIR="$PROJECT_ROOT/.build-cache/tmp"

mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" "$TMPDIR"

SWIFT_FLAGS=(--scratch-path "$PROJECT_ROOT/.build" --disable-sandbox)
