# Background Shortcut Clashes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Window Shepherd knows the global shortcuts of Rectangle and Google Drive. While Rectangle runs it steps aside on only the keys Rectangle holds, and says so once. Both apps' clashes show in Customize Shortcuts.

**Architecture:** A Core reader (`BackgroundShortcuts`) turns Rectangle's and Drive's saved preferences into `BackgroundShortcut` values. These feed `ClashSources.background`, so Customize Shortcuts lists them, and `HotkeyBinder`, which disables just the shared combos while Rectangle runs. The ⧉ menu gets one row while keys are shared. An `NSAlert` notice appears once per distinct shared-key set.

**Tech Stack:** Swift, AppKit, SwiftUI, XCTest (`swift test`), CFPreferences.

**Spec:** the design Charles approved in chat on 2026-10-23, restated here:
- **Rectangle, while running:** turn off only the Window Shepherd keys Rectangle also uses, and keep all the rest on. Bring them back about 2 s after Rectangle quits.
- **The first time they're shared, a notice** with buttons **OK** and **Show shortcuts**. Text: "Rectangle is running and uses N of the same shortcuts: K. Rectangle gets those while it runs; everything else works. To use Window Shepherd's, quit Rectangle and turn off "Launch on login" in its settings, or uninstall it." Show it again only when the shared set changes.
- **The ⧉ menu row** while keys are shared: "Rectangle is using N of your shortcuts…", which opens Customize Shortcuts.
- **Customize Shortcuts, Rectangle:** "Rectangle: <action>. Rectangle gets it while it's running."
- **Customize Shortcuts, Drive:** "Google Drive: Search. Both run. To fix it, change Drive's search key to ⌥⌘D⇧ (Drive → ⚙ → Preferences → ⚙ Settings → Configure hotkey)."
- **No second set of keys.**

## Global Constraints

- Shortcuts are always written ⌃ ⌥ ⌘ key ⇧ (`Combo.formatted` already does this).
- **Nothing may hang or slow the Mac.** Reading the preferences is a local plist read, never an app call, and is safe on the 2 s tick.
- Rectangle's default key tables are copied as data from rxhanson/Rectangle `Rectangle/WindowAction.swift` (`spectacleDefault` and `alternateDefault`, MIT). Credit it in a comment.
- **Rectangle prefs (`com.knollsoft.Rectangle`):** `alternateDefaultShortcuts` true = "Recommended" (`alternateDefault`). Missing or false = Spectacle set (Rectangle's own `BoolDefault` semantics). Per-action entries are dicts `{keyCode, modifierFlags}`, with NSEvent flags ⇧ 1<<17, ⌃ 1<<18, ⌥ 1<<19, ⌘ 1<<20. An empty dict = cleared (no key). An action with no entry uses the chosen set's default.
- **Drive prefs (`com.google.drivefs.settings`), `SearchHotKey`:** an Int64. The low 32 bits are the macOS key code; the high 32 bits are flags ⇧ 2, ⌃ 4, ⌥ 8, ⌘ 128. 0 or missing = no shortcut. Verified: 592705486853 = ⌥⌘G⇧ and 592705486850 = ⌥⌘D⇧.

## Review Focus

1. **A Rectangle key the user cleared** (`almostMaximize = {}`) must not count as shared. → Task 1 test `testClearedRectangleActionHasNoKey`.
2. **Rectangle quits while a recording is in progress** (`suspended`): keys must stay off until recording ends, then come back. → Task 2: `enable` decisions go through one function `shouldEnable(id)`.
3. **The shared set is the same at the next launch:** no notice. → Task 2 stores the noticed set in UserDefaults `rectangleNoticed`.
4. **A Rectangle key equal to a number key or the menu key** (a user's custom Rectangle setting) is also stepped aside. → Task 2 applies it to all three hotkey groups.
5. **Drive installed with its hotkey switched off** (SearchHotKey 0): no clash shown. → Task 1 test `testDriveZeroMeansNone`.

---

### Task 1: Core reader and clash text

**Files:**
- Create: `Sources/WindowShepherdCore/Scan/BackgroundShortcuts.swift`
- Modify: `Sources/WindowShepherdCore/Shortcuts/Conflicts.swift` (ClashSources, check)
- Modify: `Sources/WindowShepherdCore/Scan/ClashScanner.swift:171` (add `background: BackgroundShortcuts.live()`)
- Test: `Tests/WindowShepherdCoreTests/BackgroundShortcutsTests.swift`

**Interfaces:**
- Produces: `public struct BackgroundShortcut: Equatable { combo: Combo; app: String; what: String; effect: String }`
- Produces: `BackgroundShortcuts.rectangle(prefs: [String: Any]) -> [BackgroundShortcut]`. App "Rectangle", `what` = humanized action name ("previousDisplay" → "Previous display"), effect "Rectangle gets it while it's running."
- Produces: `BackgroundShortcuts.googleDrive(searchHotKey: Int64?) -> BackgroundShortcut?`. App "Google Drive", what "Search", with the effect text from the spec.
- Produces: `BackgroundShortcuts.live(rectangleRunning: Bool) -> [BackgroundShortcut]`. It reads both domains with `CFPreferencesCopyMultiple`/`CFPreferencesCopyAppValue`, and includes Rectangle only when it is running.
- Produces: `ClashSources.background: [BackgroundShortcut]` (default `[]`). `Conflicts.check` adds `.warn` with source = app and text `"\(app): \(what). \(effect)"`.

- [ ] **Step 1: Write the failing tests:**
  - `testRecommendedDefaults`: prefs `["alternateDefaultShortcuts": true]`. The result contains ⌃⌥⌘← "Previous display" and ⌃⌥⌘→ "Next display", and no ⌥⌘F.
  - `testSpectacleWhenFlagMissing`: prefs `[:]`. The result contains ⌥⌘F "Maximize" and ⌃⌘← "Top left".
  - `testCustomRectangleKeyOverridesDefault`: `["alternateDefaultShortcuts": true, "nextDisplay": ["keyCode": 5, "modifierFlags": 1572864]]`. "Next display" becomes ⌥⌘G (5 = G; 1572864 = ⌥⌘), and ⌃⌥⌘→ is gone.
  - `testClearedRectangleActionHasNoKey`: `["alternateDefaultShortcuts": true, "nextDisplay": [String: Any]()]`. No "Next display" entry.
  - `testDriveDecodes`: 592705486853 → ⌥⌘G⇧, and 592705486850 → ⌥⌘D⇧.
  - `testDriveZeroMeansNone`: 0 and nil → nil.
  - `testBackgroundClashText`: `Conflicts.check` with a Drive entry for ⌥⌘G⇧ yields a `.warn` whose text starts "Google Drive: Search. Both run."
- [ ] **Step 2:** Run `swift test --filter BackgroundShortcutsTests`. Expected: fails to compile (missing types).
- [ ] **Step 3: Implement.** Key names come from `KeyCodes.name(for:)` and combos from `Conflicts.fromSymbolic`. The default tables are written with key names ("left", "f", "return", "delete", "equal", "minus"), checked against `KeyCodes.fixed`.
- [ ] **Step 4:** Run `swift test`. Expected: all pass.
- [ ] **Step 5:** Commit: "Know Rectangle's and Google Drive's background shortcuts".

### Task 2: Step aside on shared keys, plus the notice

**Files:**
- Modify: `App/WindowShepherd/HotkeyBinder.swift`
- Modify: `App/WindowShepherd/AppDelegate.swift` (the notice and the menu hook)

**Interfaces:**
- Consumes: `BackgroundShortcuts.live(rectangleRunning:)`.
- Produces: `HotkeyBinder.rectangleShared: [Combo]`, the bound combos Rectangle holds now (empty when it isn't running).
- Produces: `HotkeyBinder.onRectangleSharedChanged: (([Combo]) -> Void)?`.

- [ ] **Step 1:** Replace `windowKeysOn` with `rectangleShared`. Keep hotkeys as `(id: String, hk: Hotkey)`, with one `shouldEnable(id) = !suspended && !sharedIDs.contains(id)` used by `apply`, `syncNumberKeys`, `suspend` and the menu key. `syncRectangle()` recomputes from `BackgroundShortcuts.live`, re-enables or disables, logs "Rectangle is running: N shared shortcuts off (K)" or "window shortcuts on", and calls the hook when the set changes. The launch observers call `syncRectangle` after 0.5 s; the will-launch "all off first" goes away.
- [ ] **Step 2:** In AppDelegate, when the hook fires with a non-empty set whose sorted ids differ from UserDefaults `rectangleNoticed`, show an `NSAlert` with the spec's text (K = formatted keys joined by spaces) and buttons OK / Show shortcuts. Save the ids. "Show shortcuts" opens Customize Shortcuts.
- [ ] **Step 3:** Run `scripts/build.sh Debug`. Expected: BUILD SUCCEEDED. Then `swift test` passes.
- [ ] **Step 4:** Commit: "Rectangle: step aside only on the keys it shares, and say so once".

### Task 3: Menu row

**Files:**
- Modify: `Sources/WindowShepherdCore/Menu/MenuModel.swift` (MenuInputs and build)
- Modify: `App/WindowShepherd/StatusMenuController.swift:70` (pass `binder.rectangleShared.count`)
- Test: `Tests/WindowShepherdCoreTests/MenuModelTests.swift`

**Interfaces:**
- Produces: `MenuInputs.rectangleShared: Int` (default 0).

- [ ] **Step 1: Failing test** `testRectangleRow`. With `rectangleShared = 2`, the titles contain "Rectangle is using 2 of your shortcuts…" right before "Customize shortcuts…", with action `.customize`. With 0 there's no such row. With 1 it reads "1 of your shortcuts".
- [ ] **Step 2:** Implement, then run `swift test`. Expected: pass.
- [ ] **Step 3:** Commit: "Menu: say when Rectangle holds some of your shortcuts".

### Task 4: Docs and e2e

**Files:** `README.md:59`, `docs/parity-checklist.md` (the Coexistence line), `scripts/e2e.sh:22-24`, and the HotkeyBinder doc comment.

- [ ] **Step 1:** Update the README sentence to say: shares only the keys Rectangle uses, steps aside on those while it runs, and says so. Rewrite the checklist line to "While Rectangle runs, only the keys it shares switch off (with a one-time notice and a ⧉ menu row); they come back when it quits". In e2e, keep the refusal but reword it to "Rectangle is running and holds some of the keys this test presses. Quit Rectangle first."
- [ ] **Step 2:** Commit: "Docs: Rectangle coexistence is per key now".
