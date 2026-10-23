# Changelog

All notable changes are listed here. Versions follow [Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
- First version of the standalone app, ported from the Hammerspoon window mover:
  - the ⧉ menu (action, then who: this window / the front app / everything / any app), with shortcuts shown beside rows and a full shortcut reference
  - default keyboard shortcuts: ⌥⌘ arrows / F G H C, ⌃⌘ arrow corners, add ⌃ for the whole app, add ⇧ for the next screen, ⌥⌘1–9 / ⌃⌥⌘1–9 / ⌃⌥⌘1–9⇧ for numbered screens, ⌃⌥⌘M for the menu under the mouse
  - auto-restore per screen setup, with the safeguards from the script (two sightings, three restore passes, never fighting your own moves, 30-day memory)
  - retries for apps that don't respond, named in the message, with a "Retry N windows" offer in the menu for two minutes
  - Customize Shortcuts: one recorder per action, derived shortcuts shown live, blocked (red) and ask-first (amber) clash checks against macOS, your open apps and a built-in list of popular apps' shortcuts
  - window keys switch off while Rectangle runs
- New in the app: Accessibility onboarding, Launch at Login, About, Check for Updates (Sparkle)
