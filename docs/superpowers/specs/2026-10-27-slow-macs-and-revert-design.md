# Slow Macs and Revert: design

2026-10-27. Approved by Charles, 2026-10-27.

## Why

On a Mac short on memory, apps answer slowly for a while after a screen change or wake. Window Shepherd gives each app 3 tries over about 6 seconds, and 1.5 s per window, then gives up. It doesn't say so when nothing moved.

What happened live:
- 2026-10-26 18:46: Charles plugged the Dell back in after a day on the built-in screen alone. Window Shepherd had 90 windows remembered and moved 0 across three passes, with no message. He moved 32 by hand.
- 2026-10-27: "Move to Dell, all Chrome" skipped Chrome partway. Chrome took 0.5–1.8 s per window and once didn't list its windows within 0.5 s. Four windows were refused with AX -25200 and never reported. The Retry row had expired (120 s) by the time he looked.

A second weakness: live saving keeps recording where windows sit. After a bad restore, a stranded window can become its new "home", so the next restore puts it back in the wrong place.

The goal: work properly on memory-stretched Macs, and always give the user a one-click way back to the arrangement they had.

## Goals

1. **Patience.** A restore after a screen change keeps trying apps that are slow but still answering, for up to about 60 s after the change, instead of giving up after 3 tries. Manual bulk moves get the same treatment with a shorter budget (my call: 30 s). The icon stays solid red (the existing busy state) while it works.
2. **Frozen copy per screen combination.** When the screens change away from a combination, keep a copy of where every window was in that combination, with the time. Live saving continues as now. The frozen copy changes only at the next departure from that combination. It's saved to disk, so restarts and sleep keep it.
3. **Both directions.** It works for unplugging (all screens → built-in alone) and plugging in (→ built-in + monitor), and for any combination: iMac + monitor, Mac mini + two monitors.
4. **Flashing icon when windows were left behind.** When the restore after a screen change has finished, including its patience time, and some visible windows still aren't where the frozen copy says, the ⧉ icon flashes red until the user clicks it. Opening the menu stops the flashing.
5. **Revert row at the top of the menu.** After a screen change, while a frozen copy exists for the current combination **and N > 0**, the menu's first row is one line:

   > **Put back ⟨N⟩ windows as they were at ⟨time⟩** ("Put back 1 window as it was at ⟨time⟩")

   N is counted when the menu opens: visible windows from the frozen copy whose current spot differs. When N is 0 there is no row. It never shows past the next screen change. (Changed 2026-10-28 after live use, by Charles: the first version was three lines that all did the same thing and stayed all evening, even when it would do nothing.) Clicking it moves **every** visible window in the frozen copy back to its spot, including ones arranged since the plug-in, using the same patient job. Moved windows are then recorded live as usual.
6. **Refused moves count.** A window whose move fails (an AX error, not just a slow app) counts as left behind. It's included in the retry offer and the flashing/Revert count, and the alert says so.
7. **Retry row doesn't expire after 2 minutes.** The manual-move Retry row lasts until the next move, a screen change, or every window it lists has closed.
8. **Forget closed windows.** Remembered windows that no longer exist while their app is still running are dropped. "Exist" means present in the full CoreGraphics window list (`.optionAll`, which includes other Spaces and minimized windows), not just on screen. Today Chrome shows 37 remembered and 3 open, which pads every count and plan.

9. **Windows opened while undocked (a setting, on by default).** On 2026-10-27 Charles opened 4 Safari windows on the built-in screen while unplugged. On replug they stayed there: Window Shepherd had no home for them on Built-in + Dell.

   New setting **"Windows opened while undocked"**, in Customize Shortcuts:
   - **Off**: leave them where they are, as today.
   - **On**: send them to a chosen **screen** at a chosen **size**.
     - Screen: *the biggest screen*, or *a specific screen* by its macOS name. If that screen isn't connected, use the biggest.
     - Size: *90% centered*, *full screen*, *60% centered*, or *same size, centered*.

   **Default for new installs: on, biggest screen, 90% centered** (Charles). Charles's own setting: DELL U2718Q, 90% centered.

   It applies only at a screen change that **adds** a screen. It moves visible windows that have no entry for the new combination in the live layout or the frozen copy. It runs as part of the same patient restore, after the windows that do have homes.

   Windows opened while docked are never touched by this. Once moved, these windows are recorded live like any other, so they have a home from then on.

   "Biggest" means the largest screen area, which is the existing "External" rule: the biggest non-built-in display, else the built-in.

## Non-goals

- Placing brand-new windows that open while the screens stay the same (a separate idea).
- Renaming "Laptop" elsewhere in the app ("Move to Laptop" rows, "1 = laptop" in the shortcut list, the Customize Shortcuts screen-keys text). That's a separate fix on the list. This feature never introduces the word.
- Handling windows on other Spaces differently from today (they're still put back when they appear).
- Any change to hotkeys or Customize Shortcuts.

## Anti-goals (a failure even if it works)

- **Anything that hangs or slows the Mac.** This is the project's hard rule. Patience means *more short tries spread over time*, never longer blocking calls. Every AX call keeps its 0.5 s timeout, nothing runs on the main thread, and a job never holds the worker queue while waiting.
- Moving windows the user arranged after a plug-in without their click. Only the automatic restore (as today) and an explicit Revert move things.
- Pop-up alerts or sounds to announce left-behind windows. The flashing icon is the whole signal (the existing small alert text stays as it is).
- Faint or disabled grey text in the menu (repo convention).
- A frozen copy taken from a broken arrangement replacing a good one.

## Constraints and decisions

- **Which copy gets frozen (my call, to protect the anti-goal above):** when leaving combination S, replace S's frozen copy only if S was active for at least 60 s and S has no unresolved left-behind windows. Otherwise keep the older copy. This covers the dual → single → dual flicker at every wake (seen in the log at 1–3 s), and a bad plug-in followed by a blip.
- **Live and frozen never disagree on arrival (my call).** On leaving S: if the copy is replaced, frozen = live. If the older copy is kept, live layout for S is reset to the frozen copy, so stranded spots are dropped. The automatic restore keeps planning from the live layout, unchanged, and can never rebuild a bad arrangement that was refused as a frozen copy.
- **"Left behind" and "resolved" (my call).** A window is left behind when a restore wanted to move it and, after all patience, it isn't at its spot. It stays left behind until it reaches its spot or the user moves it themselves: a hotkey or menu move, or a drag (the existing "you moved it" detection). A window the user has placed is theirs, not stranded. "Unresolved" in the freezing rule means at least one such window is still visible. Opening the menu stops the flashing but resolves nothing. The flag is updated from the cheap CoreGraphics list on the existing 2 s tick, never by asking apps.
- **Patience covers silent apps and refusals too (my call).** An app whose window list times out keeps being retried until the 60 s budget runs out, with growing waits (about 2, 4, 8, 16 s). Each try still costs at most the 0.5 s AX timeout. Windows refused with an AX error are retried within the same budget. Only when the budget runs out does a window count as left behind.
- **Interruptions (my call).** A user's bulk move during a patient restore still interrupts the job, as today. When the move finishes, the restore resumes for its remaining windows, skipping any the user has moved (the existing `restoredIds` / skip rule), within what's left of the 60 s budget. Clicking Revert cancels any running restore and replaces it.
- **Across a restart (my call).** The frozen copies and the time of the last screen change are saved to disk. After a relaunch with the same screens, the Revert row comes back. Flashing does not: a relaunch counts as having seen it.
- Closed windows are also dropped from frozen copies when forgotten (goal 8).
- The frozen copy is a copy of the live remembered layout for S at the moment of departure (`LayoutBook.layouts[key]`), plus a timestamp. Store it next to `layouts.json` in Application Support, written atomically on the existing utility queue.
- The flashing state ends when the menu opens, at the next screen change, or when a later pass or Revert leaves N = 0.
- Flashing is a cheap timer swapping the status item image (about 1 s period). My call: when the system "Reduce motion" setting is on, show the steady red icon instead of flashing.
- Counts consider only windows visible on screen now (as restores do today). Windows on other Spaces or minimized aren't counted as left behind.

## Left to the builder

- How the patience budget is expressed in `MoveTiming` / `RestoreTiming` (more retry waits, a time budget since the screen change, or both), and how `deadlineFor` extends so a 60 s patient restore isn't cut off by the job deadline.
- Whether the later scheduled passes (3/10/20 s) are folded into the patient retries or kept.
- How the menu model receives the Revert row's data (it already receives the retry offer the same way).
- Tests: unit tests in `WindowShepherdCoreTests` with `FakeWindowSystem` for patience (an app that answers on try 6 gets moved), the freezing rule (flicker and bad-plug-in cases keep the older copy), refused-window accounting, Retry row lifetime, closed-window forgetting, and Revert's plan. The live check is Charles unplugging and replugging on a busy day.
