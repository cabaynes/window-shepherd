#!/bin/bash
# Build Debug and launch it straight from this shell. A binary started this
# way counts as part of the terminal for macOS privacy checks, so it inherits
# the terminal's Accessibility permission (handy while developing).
# Logs: ~/Library/Logs/Window Shepherd/window-shepherd.log
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$(scripts/build.sh Debug | tail -1)"
osascript -e 'quit app id "com.windowshepherd.WindowShepherd"' >/dev/null 2>&1 || true
sleep 1
nohup "$APP/Contents/MacOS/Window Shepherd" >build/run-dev.out 2>&1 &
echo "launched pid $!"
