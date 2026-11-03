# App spots (memory that survives restarts and app relaunches): design

2026-11-03. Approved by Charles, 2026-11-03.

## Why

Window Shepherd knows a window only by the number macOS gives it (the CoreGraphics window ID). That number dies with the window. So every time an app quits and reopens, and every time the Mac restarts, everything remembered for that app is useless. The restore log says "N from apps that quit" and moves nothing.

What happened live, 2026-11-03:
- 08:48 restart. The Dell came up at 08:54. The restore had 33 remembered windows for Built-in + Dell and could use none of them ("33 from apps that quit").
- Safari reopened its windows by itself. One came back on the Dell 90% as wide as the screen but only as tall as the built-in screen (2707 × 1205 pt), pushed against the right edge. That's a shape Charles had never used. Before the restart all five Safari windows had sat at 90% centered on the Dell.
- Window Shepherd left it there: to it, this was a window it had never seen.

This was on file as a v1 limit ("no title matching across relaunches") but was never put to Charles in plain words. For the main use case, plugging and unplugging monitors, it's a large hole.

What Charles wants (his words, condensed): window memory is persistent, per app, per screen setup. Close and reopen an app, restart the Mac, or plug in a monitor it knows: everything goes back where it last was in that setup. His own changes, by hand or through Window Shepherd, are respected. Whatever macOS or the app guesses is overridden. Apps it has no memory of get the existing default.

## The idea

macOS gives nothing that ties a reopened window to the one before it. Browser titles change with every page, and not everyone's browser reopens old windows at all. So instead of trying to recognise individual windows, remember **where each app's windows go**.

For each screen setup (the existing setup key, display UUIDs joined), for each app (its **bundle ID**, e.g. `com.apple.Safari`, which survives restarts and reinstalls), keep a list of **spots**: a screen UUID and a unit rect, exactly what a `LayoutEntry` holds today, plus when it was last used.

A window Window Shepherd doesn't recognise goes into one of its app's **free** spots. A free spot is one no open window of that app is in.

Example, Safari on Built-in + Dell, with three windows open: laptop full screen, Dell 90% centered, and the clipped strip.
- Spots: laptop full screen and Dell 90%. The strip is **not** a spot (see "Which placements count").
- Quit Safari and reopen it with two windows: they fill both spots.
- Reopen it with one fresh window: it gets the spot used most recently.
- More windows than spots: the extras are left where the app put them.

Several windows may share a spot (five Safari windows stacked at Dell 90% are five spots at one place).

What Charles gives up: with several windows, which *page* lands in which of the app's spots may differ from before. The spots themselves are right.

## Goals

1. **App spots, saved to disk.** Per screen setup, per bundle ID, a list of spots with a last-used time. They persist across app relaunches and restarts, like `layouts.json` does today.

2. **Which placements count.** A spot is created or changed only when the placement is the user's or Window Shepherd's:
   - **A Window Shepherd move** (hotkey, menu, Revert, Retry, bulk move): counts at once, as `recordNow` does today.
   - **A Window Shepherd restore** that put the window into a remembered spot: that spot's last-used time is refreshed.
   - **The user moving a window themselves.** A window's spot changing between two snapshots counts as the user's, **except** during a "guessing period" when macOS or the app is the likely mover: shortly after that app launched, after a screen change, and after a wake. During a guessing period it still counts as the user's if the mouse was used since the previous snapshot (the existing `lastMouseUse`).
   - A window the app opened by itself that nobody moved **never** creates a spot, however long it sits there. That's what keeps Safari's clipped strip out.

   - **The undocked default** placing a window counts (it's the user's own setting doing the placing). *(My call.)*
   - **A restore to a window's own per-window entry** does not create a spot: that entry may itself be where an app put the window. *(My call.)*

   When the user moves a window that was in a spot, that spot moves with it (it is replaced, not added to). When the user places a window that wasn't in a spot, a new spot is added.

   **Last used** is refreshed while a window sits in the spot (at each snapshot), so an occupied spot never expires and "most recent" means "most recently occupied". When a window closes and its app keeps running, its spot stays: that's what lets a reopened window come back. *(My call.)*

3. **Placing windows Window Shepherd doesn't recognise.** A visible main window with no per-window entry for the current setup, and not already handled, whose app has a free spot in the current setup, is moved into a free spot:
   - **recency picks the spots, nearness pairs them.** For N unrecognised windows of an app, take its N most recently used free spots; then pair each window with the nearest of those spots to where the app opened it (the app's own reopened frame is a good matching clue, even though it's the wrong place to leave it). One fresh window always gets the most recent free spot, even if another spot is nearer. *(My call: "back to where it was last" is what Charles asked for.)*

   This happens:
   - for **every new window, at any time** (Charles): a window that appears for the first time, whether its app is starting up (every app after a restart, an app that quit and was reopened) or already running (⌘N in Safari mid-day). It's placed as soon as it's seen settled (two sightings), and only then: if the user drags it before that, or the app has no free spot, it's left where it is. A window is never placed later just because a spot became free (see anti-goals);
   - for windows already open when Window Shepherd itself starts (at login), if their app launched only shortly before;
   - at **any** screen change, in either direction, for windows with no per-window entry for the new setup. Example: a Safari window opened while docked, then the Dell is unplugged: it goes into a free laptop Safari spot instead of staying where macOS pushed it. This is part of the normal restore plan and its later passes. *(My call, from "put everything that's open back to where it last was in that saved monitor configuration".)* At a change that adds a screen, windows whose app has no spot in the new setup then get the undocked default, as today.

   Revert is unchanged: it replays the frozen per-window copy only.

   Placed windows are then tracked by their window ID as today. The per-window memory keeps recording every window as it does now, including ones an app opened that weren't placed (extras with no free spot). That is where the window actually was, so a later screen change puts it back there. Only app spots are restricted to the user's and Window Shepherd's placements. *(My call.)*

4. **Order of precedence**, for any window: its own per-window entry (today's memory, by ID, for windows that stayed open) → its app's free spot → the "Windows opened while undocked" default (only where that applies today) → leave it where it is.

5. **Main windows only.** Settings windows, dialogs, sheets, floating panels and pop-ups never take a spot and never create one. The CoreGraphics list can't tell these apart, so the Accessibility subrole (`AXStandardWindow`) is checked, and only for windows about to be placed or recorded as spots, on the worker with the usual 0.5 s timeout.

6. **The log names what it moves.** Every window moved by app spots or by the undocked default gets one line: app, window number, where it went, and why. For example, `Safari window 351 → its spot on DELL U2718Q (90% centered), opened at launch`. Today the undocked default logs only a count, which made this morning's investigation guesswork.

7. **A move checks where the window landed.** Today a move counts as done if the app accepted the new position, whatever happened next. After any move or restore, the window's frame is checked from the CoreGraphics list at the next snapshot (about 2 s later, so windows still animating aren't misjudged), not immediately over Accessibility. *(My calls, all of this goal.)*
   - **Position** off by more than a few points: the move counts as not landed.
   - **Size** counts only when it came out *smaller* than asked and the window is resizable. Sizes an app imposes (a minimum, a fixed width) are accepted, so those windows don't fail every move.
   - **Not landed:** logged with the frame it ended up at, marked left behind (flashing icon, Revert count) and offered in the manual Retry row. Never retried automatically: that would re-send a position, which `ApplyFrame` and CLAUDE.md forbid (Chrome got stuck part-way).
   - A not-landed window's frame never becomes a spot or a per-window entry (it's `protect`ed, as a failed restore is today).

8. **Day one: start from what's remembered today** (Charles). On first launch of the new version, app spots are seeded once from the live layouts (`layouts.json`) and the frozen copies, each entry becoming a spot for its app in its setup. Those entries don't record who placed a window, so some will be macOS's guesses. Charles accepts that: moving a window once replaces its bad spot. Entries whose app can't be resolved to a bundle ID (the app isn't running, and its name doesn't match an installed app) are dropped.

## Non-goals

- Recognising individual windows across relaunches by title, document or anything else. App spots replace that.
- Putting each page back in the same window it was in before.
- New settings or Customize Shortcuts changes. This is how restore works, with no switch.
- Spaces, minimized and full-screen-Space windows: handled as today.
- Changes to hotkeys or to the per-window memory for windows that stay open.

## Anti-goals (a failure even if it works)

- **Anything that hangs or slows the Mac** (the project's hard rule). Snapshots stay on the CoreGraphics list. Accessibility is asked only of apps being moved, with the 0.5 s timeout, off the main thread.
- **Fighting the user.** A window the user drags (or moves with any tool) after it opens is never pulled back.
- **Surprise jumps.** A window that has been open a while, sitting still, never suddenly moves because a spot became free.
- **A dialog or settings window grabbing a main window's spot.**
- **Learning macOS's guesses.** An app's reopened frame must never become a spot by itself sitting there.
- Faint or disabled grey text anywhere (repo convention).

## Constraints

- Public repo: no personal window titles or file names in code, tests, logs shown in docs, or this file.
- Bundle ID from `NSRunningApplication(processIdentifier:)` (cheap, no app call). Apps without one (rare helper processes) are skipped.
- Existing per-window memory, frozen copies, Revert, left-behind tracking and patience keep working as they do.
- `swift test` covers the pure parts (`LayoutBook`-style state, no screen).
- Shortcuts written ⌃ ⌥ ⌘ key ⇧.

## Left to the builder

- The data shape and file. Either alongside `layouts.json` or a new `app-spots.json`, with the same atomic-write store.
- The length of each guessing period (after an app launches, after a screen change, after a wake), and how "shortly before" Window Shepherd started counts as fresh for already-open windows. Today's numbers (60 s unsettled limit, 3/10/20 s passes) are the starting point.
- A cap on spots per app per setup and when unused spots are forgotten. The existing 30-day `forgetAfter` is the default.
- What "nearest" means for matching a window to a free spot (distance between centres on the same screen first is the obvious start).
