# Window Shepherd

Free, open-source Swift menu-bar Mac app: the standalone version of the Hammerspoon window mover in `~/CLAUDE/window-mover`. Public repo `cabaynes/window-shepherd`; website windowshepherd.com (domain bought 2026-10-19 at Squarespace).

## About the user
Non-technical founder. See universal `user_profile.md` for collaboration preferences.

## Project goals
- A free gift to Mac users who keep many windows from the same app across many apps and plug/unplug external monitors often — pitched as *different from* Rectangle, not better — and a portfolio piece for Charles (polish matters).
- v1 = **100% parity** with the Hammerspoon window mover (Charles), plus what a stranger needs: Accessibility onboarding, launch at login, About / Check for Updates / Quit.
- **Hard rule (inherited): nothing may hang or slow the Mac.**
- Published under Charles's own name (individual Apple Developer enrollment — pending). Buy Me a Coffee tip link on the website and at the bottom of Customize Shortcuts.

Design docs (private, out of repo) in `~/.claude/putdowns/window-shepherd/reference/`: the approved design `2026-10-19-window-shepherd-app-design.md`; background, APIs and hard-won lessons `window-mover-app-idea.md`; the Customize Shortcuts design and plan. Reference implementation: `~/CLAUDE/window-mover/hammerspoon/`.

**All work happens here.** The window-mover folder is frozen (2026-10-21) and retired (2026-10-23: parity passed, Hammerspoon no longer loads it), kept only for reference; don't open or change it.

## Repo layout
- `Sources/WindowShepherdCore/` — everything testable without a screen (shortcut model, clash rules, geometry, job runner, move engine `Engine/Shepherd*.swift`, auto-restore `Restore/`, menu model, clash scanner). `swift test` runs its tests.
- `App/` — the menu-bar app (XcodeGen `project.yml`; `App/*.xcodeproj` is generated, never committed). `scripts/build.sh [Debug|Release]` builds; `scripts/run-dev.sh` builds and opens.
- `Sources/wsctl`, `Sources/TestWindows` — dev tools; `scripts/e2e.sh` presses real keys on test windows (run from Terminal with permissions, not from Claude's shell). `wsctl front 10` (Terminal) prints the front app's windows in on-screen order vs. the one with keyboard focus. Debug launch flags: `open -n "<Debug app>" --args -WSOpenSettings YES -WSSnapshotSettings <png>` draws the whole Customize Shortcuts window to a 2× PNG (1360 wide) that Claude can Read; quit that copy afterwards. It shows real app menu items, which can name the user's files, so crop before publishing. `TestWindows <n> --freeze-button` adds a "Freeze for 60 s" button, for an app that stops answering.
- `vendor/Sparkle` — fetched by `scripts/fetch-sparkle.sh` (pinned version + SHA-256), gitignored.
- `docs/superpowers/specs/` and `docs/superpowers/plans/` — designs and plans (latest: 2026-10-27 slow Macs + Revert); `docs/parity-checklist.md` — the 37 lines checked live before v1 merged (all ticked 2026-10-23).
- `docs/website/content.md` — source of truth for windowshepherd.com: the pitch (Charles's three points), page outline, copy, fact-checked claims, Rectangle/competitor facts, FAQ, never-claim list.

## Conventions
- Shortcuts are always written in keyboard order ⌃ ⌥ ⌘ key ⇧ (e.g. ⌥⌘F, ⌃⌥⌘2⇧).
- Nothing the user reads is drawn faint/disabled grey.
- This repo is **public**: no secrets (signing certificates, notarization credentials, Sparkle private key), no private notes. Putdowns and OPEN-THREADS.md live out of repo at `~/.claude/putdowns/window-shepherd/`.

## External references
- Hammerspoon reference: `~/CLAUDE/window-mover` (repo cabaynes/window-mover, private; frozen 2026-10-21)
- Domain: windowshepherd.com (Squarespace DNS)

## Notes
- Claude's shell on this Mac can't drive real windows: AX calls from its process tree return stand-in elements, synthetic keystrokes are dropped, and screenshots fail (even via Hammerspoon, 2026-10-19). Live checks need the app's own Accessibility grant and `scripts/e2e.sh` run from Terminal.
- Dev builds are signed with the identity in `Config/Local.xcconfig` (gitignored) so the Accessibility grant survives rebuilds; Debug carries `disable-library-validation` for the embedded Sparkle (Release won't).
- Rectangle: no code copied; only its two default key tables, as data (credited in `Scan/BackgroundShortcuts.swift`). While it runs, Window Shepherd turns off just the keys Rectangle holds; Carbon gives a key to whoever registers first, so that happens at Rectangle's willLaunch.
- Never run `NSMenu.popUp` or `NSAlert.runModal` inside a `DispatchQueue.main` block: they block until closed, and no other main-queue work runs meanwhile (⌃⌥⌘M row clicks waited for the menu to close). Use `RunLoop.main.perform`.
- Menu-bar apps (Rectangle) aren't `.regular` activation policy: check `NSWorkspace.runningApplications` without that filter.
- Moves switch off an app's `AXEnhancedUserInterface` for the move (Rectangle's workaround): with it on, Chrome kept new sizes but dropped new positions. Never re-send a position.
- macOS 26 credits a menu bar icon to the app that launched the program: launched from Claude in VS Code, Window Shepherd's ⧉ hid until "Visual Studio Code" was allowed in System Settings → Menu Bar.
- Finder tabs are separate CoreGraphics windows stacked at one spot; only the front tab is on screen. A tab switch looks like a hidden window "appearing" — never treat it as a window coming back (`LayoutBook.dropTabSwitches`).
- Diagnose restores from `~/Library/Logs/Window Shepherd/window-shepherd.log`: each pass logs "restore plan: …" and, per app that didn't fully move, "<App>: N to move, M in its window list, K moved…". Frozen copies live in `layouts-frozen.json` beside `layouts.json`.
