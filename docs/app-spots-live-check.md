# App spots: live check list

Tick each line by hand. Run the Debug build first (`scripts/run-dev.sh`). The log is at `~/Library/Logs/Window Shepherd/window-shepherd.log`.

- [ ] 1. Put some Safari windows on the big screen at 90% and one on the laptop. Quit Safari and reopen it. The windows go back to those spots.
- [ ] 2. Restart the Mac with the big screen connected and open your usual apps. They go to their spots. The log shows "opened at launch" lines.
- [ ] 3. Press ⌘N in Safari. The new window goes to a free Safari spot. If none is free, it stays where macOS put it.
- [ ] 4. Drag a just-opened window within 2 seconds. It stays where you put it.
- [ ] 5. Open Safari Settings. It is never moved.
- [ ] 6. Unplug the big screen and plug it back in. Windows go back as before, and windows opened while unplugged go to their app's spot on the big screen.
- [ ] 7. Move System Settings with a shortcut. The log has no "didn't land" line and the window doesn't flash.
- [ ] 8. Read the log. Every window that was moved is named.
