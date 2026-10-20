#!/bin/bash
# Build the app. Usage: scripts/build.sh [Debug|Release]
# Prints the path of the built "Window Shepherd.app" on the last line.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
scripts/fetch-sparkle.sh
(cd App && xcodegen generate --quiet)
LOG="build/xcodebuild-$CONFIG.log"
mkdir -p build
if ! xcodebuild -project App/WindowShepherd.xcodeproj -scheme WindowShepherd \
    -configuration "$CONFIG" -derivedDataPath build/DerivedData build >"$LOG" 2>&1; then
  grep -E "error:|BUILD FAILED" "$LOG" | head -30
  echo "Build failed; full log: $LOG"
  exit 1
fi
grep -E "warning:" "$LOG" | grep -v "appintentsmetadataprocessor" | sort -u | head -20 || true
echo "** BUILD SUCCEEDED **"
echo "$PWD/build/DerivedData/Build/Products/$CONFIG/Window Shepherd.app"
