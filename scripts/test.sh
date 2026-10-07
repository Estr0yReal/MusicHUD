#!/bin/bash
#
# Runs the MusicHUDCore unit tests.
#
# Usage: scripts/test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$SCRIPT_DIR/env.sh"

swift test "${SWIFT_FLAGS[@]}" "$@"
