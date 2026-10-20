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
# pgrep, not `application id … is running`: that fails to compile when Rectangle isn't installed
pgrep -xq Rectangle \
  && { echo "Rectangle is running, so Window Shepherd's window keys are off. Quit Rectangle first."; exit 1; }

rm -f /tmp/ws-e2e-testwindows.out   # never read a previous run's window ids
.build/debug/TestWindows 3 --title-prefix WSTEST >/tmp/ws-e2e-testwindows.out 2>&1 &
TW=$!
trap 'kill $TW 2>/dev/null' EXIT
for _ in $(seq 20); do grep -q ready /tmp/ws-e2e-testwindows.out 2>/dev/null && break; sleep 0.25; done
# "ready <pid> <id1> <id2> <id3>": checks use window ids (titles would need Screen Recording)
read -r _ _ W1 W2 W3 < <(grep ready /tmp/ws-e2e-testwindows.out)
[ -n "${W3:-}" ] || { echo "the test windows didn't open"; exit 1; }

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
check() {   # check <name> <window id> <screen n|own> <unit…|center|default>
  local name=$1; shift
  local out
  if out=$($WSCTL check "$@"); then echo "PASS $name"; else echo "FAIL $name: $out"; FAILS=$((FAILS + 1)); fi
}

front; press 123 option command; check "⌥⌘← left half"   $W1 own 0 0 0.5 1
front; press 3   option command; check "⌥⌘F full screen"  $W1 own 0 0 1 1
front; press 5   option command; check "⌥⌘G 90%"          $W1 own 0.05 0.05 0.9 0.9
front; press 4   option command; check "⌥⌘H 60%"          $W1 own 0.2 0.2 0.6 0.6
front; press 123 option command; press 8 option command   # off-centre first, so this check can fail
                                 check "⌥⌘C center"       $W1 own center
front; press 126 control command; check "⌃⌘↑ top left"    $W1 own 0 0 0.5 0.5
front; press 124 control command; check "⌃⌘→ top right"   $W1 own 0.5 0 0.5 0.5
front; press 125 option command; check "⌥⌘↓ bottom half"  $W1 own 0 0.5 1 0.5
front; press 5 control option command
for w in $W1 $W2 $W3; do check "⌃⌥⌘G whole app (window $w)" "$w" own 0.05 0.05 0.9 0.9; done

SCREENS=$($WSCTL screens | wc -l | tr -d ' ')
if [ "$SCREENS" -ge 2 ]; then
  front; press 18 option command; check "⌥⌘1 screen 1, its default size" $W1 1 default
  front; press 19 option command; check "⌥⌘2 screen 2, its default size" $W1 2 default
  # From the bottom of screen 2: once came out short, its bottom stuck at screen 2's bottom edge
  front; press 125 option command; press 18 option command; check "⌥⌘1 from the bottom of screen 2" $W1 1 default
  front; press 19 option command
  if [ "$SCREENS" -eq 2 ]; then   # with exactly two screens, "next" is always the other one
    front; press 5 option command shift; check "⌥⌘G⇧ next screen (back to 1)" $W1 1 0.05 0.05 0.9 0.9
  fi
  front; press 19 control option command
  for w in $W1 $W2 $W3; do check "⌃⌥⌘2 whole app → screen 2 (window $w)" "$w" 2 default; done
else
  echo "SKIP screen keys (only one screen connected)"
fi

echo
[ "$FAILS" -eq 0 ] && echo "All checks passed." || echo "$FAILS check(s) failed."
exit $(( FAILS > 0 ))
