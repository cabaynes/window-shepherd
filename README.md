# Window Shepherd

[![CI](https://github.com/cabaynes/window-shepherd/actions/workflows/ci.yml/badge.svg)](https://github.com/cabaynes/window-shepherd/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-orange)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**A free, open-source menu-bar app for Mac users who keep lots of windows open, across lots of apps, and plug and unplug monitors all day.**

Unplug your external monitor and macOS piles every window onto the laptop screen. Plug it back in and they stay there. Window Shepherd remembers where every window was for each combination of screens. It puts them all back by itself, with no layouts to save first. It also gives you fast keyboard shortcuts for moving one window, or every window of an app, to wherever you want it.

> **Status:** v0.1 is in development. It's the standalone version of a Hammerspoon script I've used daily ([what changed](#from-a-script-to-an-app)). Signed downloads arrive with the first release.

## What it does

### Puts your windows back when the screens change

- Remembers every window's spot **per screen setup** ("laptop only", "laptop + Dell", "laptop + the office LG"), keyed by each display's hardware ID, so two identical monitors are still told apart.
- When the setup changes, in either direction, it puts each window back where it last was for that setup: at 3, 10 and 20 seconds, for apps that are slow to wake up.
- It never fights you. If you move a window while it's restoring, it leaves that window alone.
- A spot is recorded only after it's been seen twice, 2 seconds apart. So the moment mid-unplug, when macOS shoves everything aside, is never saved as "home".
- Windows that are minimized, hidden or on another Space are kept for 30 days rather than forgotten.

### Moves windows from the ⧉ menu

Pick an action, then who it applies to:

```
⧉ ▸ 90%  ▸  This window (Safari)          ⌥⌘G
            All Safari windows (4)         ⌃⌥⌘G
            ─────────
            Everything (23 windows)
            ─────────
            Mail (2) · Notes (1) · …
```

Actions: Full screen, 90%, 60%, Center, the four halves, the four corners, and **Move to <screen> (n): Full screen / 90% / same size**, listing only the screens the window isn't already on. Moving a whole app brings that app to the front.

### Keyboard shortcuts

Shortcuts are written in keyboard order: ⌃ ⌥ ⌘ key ⇧.

| Keys | Does |
|---|---|
| ⌥⌘ ← → ↑ ↓ | this window: left / right / top / bottom half |
| ⌥⌘F · ⌥⌘G · ⌥⌘H · ⌥⌘C | full screen · 90% · 60% · center |
| ⌃⌘ ↑ → ↓ ← | top-left · top-right · bottom-left · bottom-right corner |
| **add ⌃** | …to **every window of the app** (⌃⌥⌘G = all of Safari at 90%) |
| **add ⇧** | …on the **next screen** (⌥⌘G⇧ = this window, 90%, on the other monitor) |
| ⌥⌘1 · ⌥⌘2 … | this window → screen 1 (the laptop, full screen), 2, 3… (monitors left to right, 90%) |
| ⌃⌥⌘1 · ⌃⌥⌘2 … | the front app's windows → that screen |
| ⌃⌥⌘1⇧ · ⌃⌥⌘2⇧ … | **everything** → that screen |
| ⌃⌥⌘M | the ⧉ menu, under the mouse |

More keys means more windows. Every shortcut can be changed in **⧉ → Customize shortcuts…**: click a box and press the new keys. The window shows each derived shortcut beside it. Clashes with Window Shepherd itself, or with a macOS shortcut that would take the key first, are blocked in red. If an app uses the keys (it reads the menus of your open apps, plus a built-in list of 429 shortcuts from popular apps), it shows the clash in amber and asks before applying.

## Different from Rectangle, not better

[Rectangle](https://github.com/rxhanson/Rectangle) is excellent and free, and Window Shepherd's single-window keys deliberately match its defaults. If you use Rectangle, Window Shepherd switches its own window keys off while Rectangle is running, and back on when it quits. Rectangle snaps one window at a time. Window Shepherd is built around different moments: the unplug, the replug, and "move all of these over there".

Apps that restore layouts already exist and are good: [Stay](https://cordlessdog.com/stay), [Moom](https://manytricks.com/moom/), [Display Maid](https://apps.apple.com/us/app/display-maid/id450063525?mt=12) and [Rectangle Pro](https://rectangleapp.com/pro). Most ask you to save a layout first. Window Shepherd remembers continuously, so there's nothing to set up. It's free and open source.

## How it stays fast

The rule this app is built around: **nothing may hang or slow the Mac.** Window managers talk to other apps through the Accessibility API, and an app that's busy or hung can stall whoever is asking. The first version of the script froze my laptop this way, so every design decision follows from that lesson:

- **The menu and the auto-restore memory never talk to apps.** They read macOS's window list (CoreGraphics), which takes a few hundredths of a second and can't block on a hung app. Only an actual move talks to an app, and only to apps that have a window on screen.
- **Every question to an app times out after 0.5 s**, and the main thread never asks. All Accessibility calls run on background queues, so the menu, the shortcuts and the ⧉ icon stay responsive whatever other apps are doing.
- **"Busy" isn't "hung".** Safari can take 0.3–0.4 s to resize a window while it re-lays out pages. An app is called "not responding" only if it can't even list its windows, or one window takes over 0.8 s. It's then retried 2 s and 4 s later, and named, not dropped silently. For two minutes afterwards, the menu offers "Retry N windows that didn't move".
- **Work is done one window at a time** with a hard deadline per job. A new move interrupts an old one, and a keyboard snap never waits behind a restore. Each app has its own lane, so a hung app delays only itself.
- **The only polling is a cheap 2-second check** of the screen setup. It reads the window list only, which also catches screen changes macOS forgot to announce (after sleep, for example).
- **The ⧉ turns red** while a move or restore is running, so you know when to keep your hands off.

The engine is covered by more than 140 unit tests. They include a fake "hung app" that must not delay the main thread or other apps, screens unplugged mid-move, and restores you interrupt by moving a window yourself.

## Install

> Coming with the first release: a signed and notarized download from [Releases](https://github.com/cabaynes/window-shepherd/releases), and `brew install --cask cabaynes/tap/window-shepherd`.

On first launch Window Shepherd asks for one permission, **Accessibility**, which every window manager needs to move windows. It walks you through it and notices by itself once it's granted. It can also start at login (on by default, switchable from the menu).

## Privacy

Window Shepherd collects nothing. Its only network connection is the update check (Sparkle), which downloads an update feed from GitHub. It never reads what's inside your windows. It stores two things on your Mac: your shortcuts and where your windows were. See [PRIVACY.md](PRIVACY.md).

## Building from source

Requirements: Xcode 16 or newer, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
swift test                 # the engine's unit tests (no screen needed)
scripts/build.sh Debug     # generates the Xcode project and builds the app
scripts/run-dev.sh         # builds and opens it
```

Builds are signed ad-hoc by default. To keep the Accessibility permission across rebuilds, put your own signing identity in `Config/Local.xcconfig` (gitignored):

```
CODE_SIGN_IDENTITY = Apple Development
```

`scripts/e2e.sh` presses every default shortcut on throwaway test windows and checks where they land. Run it from Terminal with Window Shepherd open.

### Layout

| Path | What's there |
|---|---|
| `Sources/WindowShepherdCore/` | Everything testable without a screen: the shortcut model and clash rules, geometry, the job runner, the move engine, auto-restore |
| `App/WindowShepherd/` | The menu-bar app: status menu, Carbon hotkeys, Customize Shortcuts window, onboarding, updates |
| `Tests/` | Unit tests (`swift test`) |
| `Sources/wsctl`, `Sources/TestWindows` | Developer tools used by `scripts/e2e.sh` |
| `docs/` | The implementation plan, the parity checklist, release notes for maintainers |

## From a script to an app

Window Shepherd started as a Hammerspoon script that I used every day for weeks, and v1 is a faithful port of it, down to the wording of its messages. The [parity checklist](docs/parity-checklist.md) tracks that, line by line. Moving to a real app made a few things possible that the script couldn't do: Accessibility calls off the main thread, a native settings window, and an install that doesn't need Hammerspoon.

## Support

Window Shepherd is free. If it saves you time, you can [buy me a coffee ☕](https://buymeacoffee.com/cccccccharles).

Made by Charles Baynes · [windowshepherd.com](https://windowshepherd.com) · MIT license
