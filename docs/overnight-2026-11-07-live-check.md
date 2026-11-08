# Overnight batch (2026-11-07): live check list

The changes from the night of 2026-11-07 passed 350 unit tests, but only the Get Info fix has been seen working on a real Mac. Tick each line by hand. Run the latest Debug build (`scripts/run-dev.sh`, or quit Window Shepherd from the ⧉ menu and reopen it).

Some lines ask you to read the log. To open it, paste this into Terminal and press Return:

    open ~/Library/Logs/"Window Shepherd"/window-shepherd.log

In Console, type a word into the search box at the top to find a line.

## Most worth checking

- [ ] 1. Open Customize Shortcuts (⧉ menu). Under the rows there's one amber line like "⚠ 2 potential conflicts (Window Shepherd wins) ▸" instead of a box. Click it: the list opens. Click again: it closes. (WS-217)
- [ ] 2. Put a window in full screen (the green button). Unplug the Dell and plug it back in. That window is left alone, the ⧉ icon doesn't flash, and the log says "is in full screen: left alone". (WS-226)
- [ ] 3. Click a full-screen window and press 90% (⌥⌘G). A message says it's in full screen and Window Shepherd leaves it where it is. (WS-226)
- [ ] 4. With several Chrome windows open, move them all at once (⌃⌥⌘G, every window of the app). They all move, and quickly. If Chrome has enhanced UI on, the log says "switching it off while moving its windows" once, not once per window. (WS-228)
- [ ] 5. Plug the Dell in and, before the windows finish going back, press a shortcut on one window (90%, say). It stays where your key put it; the restore doesn't put it back. (WS-229)

## Quick ones

- [ ] 6. Open Get Info on a file in Finder. The panel stays where Finder opens it. (Already checked 2026-11-07.)
- [ ] 7. After the Mac sleeps and wakes, the log has a "Mac woke from sleep" line. (WS-224)
- [ ] 8. Click into a text field right after a shortcut move (no drag). Nothing odd happens; if the move didn't land, it's still offered in Retry. (WS-435)

## If something is wrong

Note the time, then tell Claude. The log names every window it moved, and `.build/debug/wsctl cg "<App name>"` shows what macOS reports about an app's windows.
