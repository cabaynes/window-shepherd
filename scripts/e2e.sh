#!/bin/bash
# End-to-end check of the real app with real keys, on throwaway test windows.
#
# Run it from Terminal (not from inside Claude Code), after:
#   1. Window Shepherd is running and has the Accessibility permission, and
#   2. Terminal is allowed to control your computer (System Settings →
#      Privacy & Security → Accessibility → Terminal), so it can press keys.
# The first run asks "Terminal wants to control System Events" — click OK.
#
# It opens three "WSTEST" windows, presses each default shortcut, and reads
# where the window ended up from macOS's window list. Your own windows are
# never touched (the test windows are brought to the front first).
#
#   scripts/e2e.sh          # prints PASS/FAIL per check, exits 1 on any FAIL
set -uo pipefail
cd "$(dirname "$0")/.."

swift build -c debug >/dev/null 2>&1 || { echo "swift build failed"; exit 1; }
WSCTL=.build/debug/wsctl
osascript -e 'application id "com.windowshepherd.WindowShepherd" is running' | grep -q true \
  || { echo "Window Shepherd isn't running — open it first."; exit 1; }

.build/debug/TestWindows 3 --title-prefix WSTEST >/tmp/ws-e2e-testwindows.out 2>&1 &
TW=$!
trap 'kill $TW 2>/dev/null' EXIT
for _ in $(seq 20); do grep -q ready /tmp/ws-e2e-testwindows.out 2>/dev/null && break; sleep 0.25; done

FAILS=0
front() {   # bring the test windows to the front, "WSTEST 1" on top
  osascript -e 'tell application "System Events" to tell process "TestWindows"' \
            -e 'set frontmost to true' -e 'perform action "AXRaise" of window "WSTEST 1"' -e 'end tell' >/dev/null 2>&1
  sleep 0.4
}
press() {   # press <key code> <modifiers…> (e.g. press 5 option command)
  local code=$1; shift
  local mods=""
  for m in "$@"; do mods+="${mods:+, }$m down"; done
  osascript -e "tell application \"System Events\" to key code $code using {$mods}"
  sleep 0.8
}
check() {   # check <name> <window title> <screen n|own> <unit…|center>
  local name=$1; shift
  local out
  if out=$($WSCTL check "$@"); then echo "PASS $name"; else echo "FAIL $name: $out"; FAILS=$((FAILS + 1)); fi
}

front; press 123 option command; check "⌥⌘← left half"   "WSTEST 1" own 0 0 0.5 1
front; press 3   option command; check "⌥⌘F full screen"  "WSTEST 1" own 0 0 1 1
front; press 5   option command; check "⌥⌘G 90%"          "WSTEST 1" own 0.05 0.05 0.9 0.9
front; press 4   option command; check "⌥⌘H 60%"          "WSTEST 1" own 0.2 0.2 0.6 0.6
front; press 8   option command; check "⌥⌘C center"       "WSTEST 1" own center
front; press 126 control command; check "⌃⌘↑ top left"    "WSTEST 1" own 0 0 0.5 0.5
front; press 124 control command; check "⌃⌘→ top right"   "WSTEST 1" own 0.5 0 0.5 0.5
front; press 125 option command; check "⌥⌘↓ bottom half"  "WSTEST 1" own 0 0.5 1 0.5
front; press 5 control option command
for n in 1 2 3; do check "⌃⌥⌘G whole app (window $n)" "WSTEST $n" own 0.05 0.05 0.9 0.9; done

SCREENS=$($WSCTL screens | wc -l | tr -d ' ')
if [ "$SCREENS" -ge 2 ]; then
  front; press 18 option command; check "⌥⌘1 laptop, full screen" "WSTEST 1" 1 0 0 1 1
  front; press 19 option command; check "⌥⌘2 screen 2, 90%"       "WSTEST 1" 2 0.05 0.05 0.9 0.9
  front; press 5 option command shift; check "⌥⌘G⇧ next screen (back to 1)" "WSTEST 1" 1 0.05 0.05 0.9 0.9
  front; press 19 control option command
  for n in 1 2 3; do check "⌃⌥⌘2 whole app → screen 2 (window $n)" "WSTEST $n" 2 0.05 0.05 0.9 0.9; done
else
  echo "SKIP screen keys (only one screen connected)"
fi

echo
[ "$FAILS" -eq 0 ] && echo "All checks passed." || echo "$FAILS check(s) failed."
exit $(( FAILS > 0 ))
