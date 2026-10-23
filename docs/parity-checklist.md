# Parity checklist

Window Shepherd v1 must do everything the Hammerspoon window mover did. This list comes from the design's Goal 1, plus every default shortcut. The Hammerspoon mover is retired only when every line has been checked on the real Mac, including one real unplug and replug of the external monitor. Until then it stays the daily driver; it pauses itself whenever Window Shepherd is running.

Legend: **A** = `scripts/e2e.sh` checks it automatically · **M** = check by hand · **U** = covered by unit tests (`swift test`).

## Menu (⧉)

- [x] **M U** The ⧉ menu lists actions first, then the scope: This window / All <front app> windows / Everything / every other app A–Z
- [x] **M U** Shortcuts appear beside the action rows and the scope rows, in ⌃ ⌥ ⌘ key ⇧ order
- [x] **M U** "Keyboard shortcuts" submenu: every shortcut, in full-strength text (not grey)
- [x] **M U** "Move to <screen> (n) — Full screen / 90% / same size" lists only screens the front window isn't on
- [ ] **M U** With one screen connected, the "Move to" section is hidden
- [ ] **M U** A "Move to" chosen after its screen was unplugged says "<name> (n) isn't connected anymore"
- [x] **M** The ⧉ turns red while a move or restore is running
- [x] **M** ⌃⌥⌘M opens the menu under the mouse
- [x] **M** The bottom of the menu: Customize shortcuts…, Keyboard shortcuts, Launch at Login, About Window Shepherd, Check for Updates…, Quit Window Shepherd

## Keyboard shortcuts (defaults)

| Keys | Does | How |
|---|---|---|
| ⌥⌘← ⌥⌘→ ⌥⌘↑ ⌥⌘↓ | this window: left / right / top / bottom half | A (← and ↓), M (→ ↑) |
| ⌥⌘F | this window: full screen | A |
| ⌥⌘G | this window: 90% | A |
| ⌥⌘H | this window: 60% | A |
| ⌥⌘C | this window: centered, same size | A |
| ⌃⌘↑ ⌃⌘→ ⌃⌘← ⌃⌘↓ | this window: top-left / top-right / bottom-left / bottom-right corner (← and ↓ swapped from the Hammerspoon mover, Charles 2026-10-23) | A (↑ →), M (← ↓) |
| add ⌃ (e.g. ⌃⌥⌘G) | every window of the front app | A (⌃⌥⌘G) |
| add ⇧ (e.g. ⌥⌘G⇧) | on the next screen | A (⌥⌘G⇧) |
| ⌃ and ⇧ (e.g. ⌃⌥⌘G⇧) | every window of the app, on the next screen | M |
| ⌥⌘C⇧ | this window to the next screen, same size | M |
| ⌥⌘1 / ⌥⌘2 … | this window → screen n (laptop full screen, monitors 90%) | A |
| ⌃⌥⌘1 / ⌃⌥⌘2 … | the front app's windows → screen n | A (⌃⌥⌘2) |
| ⌃⌥⌘1⇧ / ⌃⌥⌘2⇧ … | everything → screen n | M |
| ⌃⌥⌘M | the menu under the mouse | M |

- [ ] **M U** Number keys exist only for screens that are connected (and only with 2 or more screens)
- [ ] **M** Single-window keyboard moves are silent; bulk moves show "Moved N windows → …"
- [ ] **M** A whole-app move brings that app to the front; an "Everything" move doesn't change the front app

## Auto-restore

- [ ] **M U** Every window's spot is remembered per combination of connected screens
- [ ] **U** A spot is recorded only after it's been seen twice, about 2 s apart
- [ ] **M U** After a screen change, windows go back at +3 / +10 / +20 s
- [ ] **M U** A window you move during those passes isn't put back
- [ ] **U** Spots macOS dumped windows in aren't recorded as their home
- [ ] **U** Windows unseen for 30 days are forgotten (minimized and other-Space windows are kept until then)
- [ ] **M** Remembered spots survive quitting and reopening the app
- [ ] **M** **One real unplug → replug of the Dell** puts every window back

## Apps that don't respond

- [ ] **U** An app that doesn't answer is retried 2 s and 4 s later within the same job, then skipped and named in the message
- [ ] **M U** For 2 minutes the menu offers "Retry N windows that didn't move", listing them

## Customize Shortcuts window

- [ ] **M** One recorder box per action; derived chips (whole app / next screen / both) beside each
- [ ] **M** ⌃⌥⌘⇧ toggles for the two "add a key" modifiers and the screen keys
- [ ] **M U** Red = blocked (clashes with Window Shepherd itself, or macOS would take it first)
- [ ] **M U** Amber = used by an app; Keep or Cancel before it applies
- [ ] **M** A change made while "Checking your open apps…" waits for the check
- [ ] **M** Keys without ⌃/⌥/⌘ are ignored while recording ("Hold ⌃, ⌥ or ⌘ too"); Esc cancels
- [ ] **M U** ⌘Tab and ⌘\` can't be used
- [ ] **M** ↺ per row and Reset all
- [ ] **M** Clicking another window stops recording
- [ ] **M** "Buy me a coffee" link at the bottom opens buymeacoffee.com/cccccccharles

## Coexistence

- [ ] **M** Action keys switch off while Rectangle runs, and back on when it quits
- [ ] **M** The Hammerspoon mover pauses while Window Shepherd runs, and comes back when it quits (verified 2026-10-19 by Claude: pause/resume logged, ⧉ icon hidden and restored, 51 hotkeys live after resume)

## New for strangers

- [ ] **M** First launch without permission shows the Accessibility onboarding; it notices when permission is granted
- [ ] **M** Launch at Login is on after onboarding and can be switched off
- [ ] **M** About shows the version, Charles Baynes and windowshepherd.com
