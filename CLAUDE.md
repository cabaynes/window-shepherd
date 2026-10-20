# Window Shepherd

Free, open-source Swift menu-bar Mac app: the standalone version of the Hammerspoon window mover in `~/CLAUDE/window-mover`. Public repo `cabaynes/window-shepherd`; website windowshepherd.com (domain bought 2026-10-19 at Squarespace).

## About the user
Non-technical founder. See universal `user_profile.md` for collaboration preferences.

## Project goals
- A free gift to Mac users who keep many windows from the same app across many apps and plug/unplug external monitors often — pitched as *different from* Rectangle, not better — and a portfolio piece for Charles (polish matters).
- v1 = **100% parity** with the Hammerspoon window mover (Charles), plus what a stranger needs: Accessibility onboarding, launch at login, About / Check for Updates / Quit.
- **Hard rule (inherited): nothing may hang or slow the Mac.**
- Published under Charles's own name (individual Apple Developer enrollment — pending). Buy Me a Coffee tip link on the website and at the bottom of Customize Shortcuts.

The approved design: `~/CLAUDE/window-mover/docs/superpowers/specs/2026-10-19-window-shepherd-app-design.md`. Background, APIs and hard-won lessons: `~/CLAUDE/window-mover/docs/window-mover-app-idea.md`. Reference implementation: `~/CLAUDE/window-mover/hammerspoon/`.

## Repo layout
- `Sources/WindowShepherdCore/` — everything testable without a screen (shortcut model, clash rules, geometry, job runner, move engine `Engine/Shepherd*.swift`, auto-restore `Restore/`, menu model, clash scanner). `swift test` runs its tests.
- `App/` — the menu-bar app (XcodeGen `project.yml`; `App/*.xcodeproj` is generated, never committed). `scripts/build.sh [Debug|Release]` builds; `scripts/run-dev.sh` builds and opens.
- `Sources/wsctl`, `Sources/TestWindows` — dev tools; `scripts/e2e.sh` presses real keys on test windows (run from Terminal with permissions, not from Claude's shell).
- `vendor/Sparkle` — fetched by `scripts/fetch-sparkle.sh` (pinned version + SHA-256), gitignored.
- `docs/superpowers/plans/` — the v1 plan; `docs/parity-checklist.md` — what must be verified before the Hammerspoon mover is retired.

## Conventions
- Shortcuts are always written in keyboard order ⌃ ⌥ ⌘ key ⇧ (e.g. ⌥⌘F, ⌃⌥⌘2⇧).
- Nothing the user reads is drawn faint/disabled grey.
- This repo is **public**: no secrets (signing certificates, notarization credentials, Sparkle private key), no private notes. Putdowns and OPEN-THREADS.md live out of repo at `~/.claude/putdowns/window-shepherd/`.

## External references
- Hammerspoon reference: `~/CLAUDE/window-mover` (repo cabaynes/window-mover, private)
- Domain: windowshepherd.com (Squarespace DNS)

## Notes
- Claude's shell on this Mac can't drive real windows: AX calls from its process tree return stand-in elements, synthetic keystrokes are dropped, and screenshots fail (even via Hammerspoon, 2026-10-19). Live checks need the app's own Accessibility grant and `scripts/e2e.sh` run from Terminal.
- Dev builds are signed with the identity in `Config/Local.xcconfig` (gitignored) so the Accessibility grant survives rebuilds; Debug carries `disable-library-validation` for the embedded Sparkle (Release won't).
- The Hammerspoon mover (window-mover repo) pauses only while the app posts `com.windowshepherd.WindowShepherd.active` = "1".
- No Rectangle code was copied, so LICENSE carries no Rectangle notice.
