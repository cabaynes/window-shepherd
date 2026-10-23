#!/bin/bash
# Build Debug and open it. The app needs its own Accessibility permission
# (System Settings → Privacy & Security → Accessibility); with a stable
# signing identity in Config/Local.xcconfig the permission survives rebuilds.
# Logs: ~/Library/Logs/Window Shepherd/window-shepherd.log
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$(scripts/build.sh Debug | tail -1)"
osascript -e 'quit app id "com.windowshepherd.WindowShepherd"' >/dev/null 2>&1 || true
sleep 1
open "$APP"
echo "opened $APP"
