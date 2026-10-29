# Privacy

Window Shepherd collects nothing and sends nothing about you anywhere.

- **Network:** the only connection it makes is the update check. Sparkle downloads the update feed (`appcast.xml`) from GitHub Pages, and an update only if you choose to install it. There is no analytics, telemetry or crash reporting.
- **Accessibility permission:** used only to move and resize windows, and to read which shortcuts open apps' menus use (shown only while the Customize Shortcuts window is open). It never reads what's inside your windows.
- **Other preferences it reads, while Customize Shortcuts is open:** macOS's keyboard-shortcut settings (`com.apple.symbolichotkeys`) and the custom app shortcuts you set in System Settings (`NSUserKeyEquivalents` in each app's preferences), to warn about clashes. Nothing is copied or kept.
- **Two other apps' shortcut settings:** Google Drive's search shortcut (`SearchHotKey` in `com.google.drivefs.settings`), shown as a clash in Customize Shortcuts; and, only while Rectangle is running, Rectangle's shortcuts (`com.knollsoft.Rectangle`), checked every 2 seconds so Window Shepherd can step aside on the keys Rectangle uses. It reads only those shortcut settings, and keeps nothing.
- **What it stores, on your Mac only:**
  - your shortcuts (in the app's preferences)
  - where your windows were for each screen setup: window number, app name, position (`~/Library/Application Support/Window Shepherd/layouts.json`), forgotten after 30 days unseen or when the window closes
  - a frozen copy of the same, taken when you unplug, for Revert (`layouts-frozen.json` in the same folder)
  - a small log of what it did, for troubleshooting (`~/Library/Logs/Window Shepherd/`, under 512 KB)

Delete those files and the app's preferences, and nothing of it remains.
