#!/bin/bash
set -euo pipefail

# =============================================================================
# build-local.sh — Terminal-only local build for Clicky (no Xcode GUI needed)
#
# Builds the app with ad-hoc code signing. It uses the Xcode at
# /Applications/Xcode.app even when `xcode-select` points at the Command Line
# Tools, and overrides the project's hardcoded DEVELOPMENT_TEAM so no Apple
# Developer account is required.
#
# Caveat: ad-hoc builds get a new signature every time, so macOS may ask you to
# re-grant Screen Recording / Accessibility permissions after a rebuild.
#
# Overridable via environment variables:
#   XCODE_DEVELOPER_DIR  (default: /Applications/Xcode.app/Contents/Developer)
#   DERIVED_DATA_PATH    (default: <repo>/build)
# =============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_DEVELOPER_DIR="${XCODE_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$REPO_ROOT/build}"

if [[ ! -d "$XCODE_DEVELOPER_DIR" ]]; then
  echo "error: Xcode not found at $XCODE_DEVELOPER_DIR" >&2
  echo "Install Xcode, or set XCODE_DEVELOPER_DIR to its Developer directory." >&2
  exit 1
fi

export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"

echo "Building Clicky (ad-hoc signed)…"
xcodebuild \
  -project "$REPO_ROOT/leanring-buddy.xcodeproj" \
  -scheme leanring-buddy \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/Clicky.app"
echo
echo "Built: $APP_PATH"
echo "Run it with:  scripts/run-local.sh    (or: open \"$APP_PATH\")"
