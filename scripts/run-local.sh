#!/bin/bash
set -euo pipefail

# =============================================================================
# run-local.sh — Launches the locally built Clicky app
#
# Build it first with scripts/build-local.sh. The app lives in the menu bar
# (no dock icon, no main window), so look for the icon next to the clock.
# =============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$REPO_ROOT/build}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/Clicky.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app not built yet at $APP_PATH" >&2
  echo "Run scripts/build-local.sh first." >&2
  exit 1
fi

echo "Launching $APP_PATH"
open "$APP_PATH"
