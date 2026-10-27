# Slow Macs and Revert Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Window Shepherd keeps working on memory-stretched Macs. It is patient with slow apps, freezes a known-good layout per screen combination, flashes the icon and offers a one-click Revert when windows are left behind, and sends windows opened while undocked to a chosen screen.

**Architecture:** Patience lives in `appStep` (MoveStep.swift), as a deadline (`patientUntil`) instead of a fixed try count. Restores and bulk moves pass one in. Frozen copies, left-behind tracking and "homeless" windows are pure state in `LayoutBook`, persisted by a new `FrozenStore`. `Shepherd` exposes `flashing`, `revertInfo()` and `revert()`. The app draws the flashing icon, the Revert rows, and a new section in Customize Shortcuts.

**Tech Stack:** Swift 6, AppKit/SwiftUI, XCTest (`swift test`), XcodeGen app build (`scripts/build.sh`).

**Spec:** `docs/superpowers/specs/2026-10-27-slow-macs-and-revert-design.md`

## Global Constraints

- Nothing may hang or slow the Mac. Every AX call keeps the 0.5 s timeout (`axTimeout`), and nothing new runs on the main thread except CoreGraphics list reads. Waits are job steps that return a wait (`waitStep`), never sleeps.
- Never write "laptop" in any new user-visible text. Name screens with `Screens.setupLabel` / `ScreenInfo.name`.
- Nothing the user reads is drawn faint or disabled grey.
- Shortcuts in docs and comments are written in the order ⌃ ⌥ ⌘ key ⇧.
- Restore patience 60 s from the screen change. Bulk-move patience 30 s.
- Frozen-copy rule: replace on departure only if the combination was active ≥ 60 s and has no unresolved left-behind windows. Otherwise roll the live layout back to the frozen copy.
- Undocked default: on, biggest screen, 90% centered.
- Revert row copy, exactly:
  - `Revert <setupLabel>`
  - `to how it was at <time>, before they were separated`
  - `<N> window(s) aren't where they were then` / `1 window isn't where it was then` / `Every window is where it was then`

## Review Focus

1. **Screens flicker (on, off, on within 1–3 s) at every wake.** Expect no frozen copy replaced, the restore restarted cleanly, and the patience clock based on the *latest* change. Test in Task 5 (`testFlickerKeepsFrozenCopy`).
2. **A user drags a stranded window somewhere new.** Expect it no longer left behind: the icon stops flashing once none remain, and the next unplug may freeze. Test in Task 5 (`testUserMoveResolvesLeftBehind`).
3. **An app that never answers (truly hung) during 60 s of patience.** Expect each try capped at 0.5 s, waits growing to 16 s, other apps moved meanwhile, and the menu and hotkeys working throughout. Test in Task 1 (`testPatientRetriesUntilDeadlineThenGivesUp`, checks list calls ≤ 6 in 0.6 s scaled time).
4. **Revert clicked while a restore is running, or with no frozen copy.** Expect the running restore stopped and replaced. With no copy, no row. Test in Task 6 (`testRevertCancelsRunningRestore`, `testNoRevertRowWithoutFrozenCopy`).
5. **The named undocked screen isn't connected.** Expect a fallback to the biggest screen. Test in Task 7 (`testNamedScreenMissingFallsBackToBiggest`).

---

### Task 1: Patient app steps

**Files:**
- Modify: `Sources/WindowShepherdCore/Engine/MoveStep.swift`
- Test: `Tests/WindowShepherdCoreTests/MoveStepTests.swift`

**Interfaces:**
- Produces:
  - `appStep(..., patientUntil: Date? = nil, ...)`, a new parameter after `partly:`. `nil` keeps today's behavior: `retryWaits.count` retries, then give up.
  - `Tally.refused: [pid_t: [UInt32: V]]`: windows whose move threw after patience ran out. They are also merged into `missed`.
  - `reportText(_:skipped:hasMissed:problem:refused:)` with a new `refused: Int = 0`.
  - `MoveTiming.maxWait: TimeInterval = 16`.

- [ ] **Step 1: Write the failing tests**

```swift
func testPatientRetriesUntilAppAnswers() async {
    let sys = FakeWindowSystem()
    sys.addApp(10, "Slow", windows: [(1, .zero)])
    sys.listBehaviour[10] = .throwTimes(5)          // answers on the 6th try
    let tally = await runPatient(sys, pid: 10, wanted: [1: true], for: 2)   // helper: patientUntil = now + 2 s
    XCTAssertEqual(tally.moved, 1)
    XCTAssertEqual(sys.listCalls[10], 6)
}

func testPatientRetriesUntilDeadlineThenGivesUp() async {
    let sys = FakeWindowSystem()
    sys.addApp(10, "Hung", windows: [(1, .zero)])
    sys.listBehaviour[10] = .throwAlways
    let tally = await runPatient(sys, pid: 10, wanted: [1: true], for: 0.6)
    XCTAssertEqual(tally.skipped, ["Hung"])
    XCTAssertEqual(Set(tally.missed[10]!.keys), [1])
    XCTAssertLessThanOrEqual(sys.listCalls[10]!, 6)   // waits grow: never a tight loop
}

func testRefusedWindowRetriedWithinPatience() async {
    let sys = FakeWindowSystem()
    sys.addApp(10, "Fake", windows: [(1, .zero), (2, .zero)])
    sys.failSet = [2]
    Task { try? await Task.sleep(nanoseconds: 150_000_000); sys.locked { sys.failSet = [] } }
    let tally = await runPatient(sys, pid: 10, wanted: [1: true, 2: true], for: 2)
    XCTAssertEqual(tally.moved, 2)
    XCTAssertTrue(tally.refused.isEmpty)
}

func testRefusedAfterPatienceCountsAsMissed() async {
    let sys = FakeWindowSystem()
    sys.addApp(10, "Fake", windows: [(1, .zero), (2, .zero)])
    sys.failSet = [2]
    let tally = await runPatient(sys, pid: 10, wanted: [1: true, 2: true], for: 0.3)
    XCTAssertEqual(Set(tally.refused[10]!.keys), [2])
    XCTAssertEqual(Set(tally.missed[10]!.keys), [2])
    XCTAssertEqual(reportText("Moved 1 window", skipped: [], hasMissed: true, problem: nil, refused: 1),
                   "Moved 1 window\n(1 window refused to move)\nRetry from the ⧉ menu")
}
```

`runPatient` mirrors the existing `run` helper, with `timing = MoveTiming(windowLimit: 0.8, listSlow: 0.4, retryWaits: [0.05, 0.1])` and `maxWait = 0.2`, and passes `patientUntil: Date().addingTimeInterval(seconds)` with a job deadline of `seconds + 2`. The existing tests keep passing `nil`.

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter MoveStepTests`
Expected: compile failure (`patientUntil`, `refused` unknown).

- [ ] **Step 3: Implement**

In `giveUp`, with `patientUntil` set: the wait for try *n* is `retryWaits[n-1]` while it exists, then doubles, capped at `maxWait`. Retry while `Date() + wait < patientUntil`. Otherwise give up exactly as today.

In the trailing summary step: if `refused` is non-empty and patience allows another wait, queue `waitStep` plus an `appStep` for just the refused windows (same retry rule, `partly: true` if any moved). Otherwise put them in `tally.refused[pid]` and `tally.missed[pid]`.

`reportText` adds `\n(N window(s) refused to move)` when `refused > 0`. Add `\nRetry from the ⧉ menu` when `hasMissed` and the line isn't already there.

- [ ] **Step 4: Run tests**

Run: `swift test --filter MoveStepTests`, then `swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

`git commit -am "Patient app steps: retry slow apps and refused windows until a deadline"`

---

### Task 2: Restores and bulk moves use patience

**Files:**
- Modify: `Sources/WindowShepherdCore/Engine/Shepherd+Restore.swift`, `Sources/WindowShepherdCore/Engine/Shepherd.swift`, `Sources/WindowShepherdCore/Engine/MoveStep.swift` (MoveTiming)
- Test: `Tests/WindowShepherdCoreTests/ShepherdRestoreTests.swift`, `Tests/WindowShepherdCoreTests/ShepherdMoveTests.swift`

**Interfaces:**
- Consumes: `appStep(patientUntil:)` and `Tally.refused` (Task 1).
- Produces:
  - `RestoreTiming.patience: TimeInterval = 60`
  - `MoveTiming.movePatience: TimeInterval = 30`
  - `Shepherd.resumeRestore: Bool` (internal)

- [ ] **Step 1: Write the failing tests**

```swift
// ShepherdRestoreTests
func testRestoreWaitsForSlowApp() async {        // restoreTiming patience 1.5 s in make()
    let s = await rememberedThenUnplugged()
    sys.listBehaviour[10] = .throwTimes(sys.listCalls[10, default: 0] + 4)
    sys.allScreens = [lap, dell]; s.tick()
    await waitUntil(4) { !s.isBusy }
    XCTAssertEqual(sys.frameOf(1)?.minX ?? 0, 1100, accuracy: 2)
}

func testInterruptedRestoreResumesAfterMove() async {
    let s = await rememberedThenUnplugged()
    sys.addApp(20, "Notes", windows: [(5, rect(60))])
    sys.setDelay[1] = 0.2
    sys.allScreens = [lap, dell]; s.tick()
    try? await Task.sleep(nanoseconds: 120_000_000)   // restore running
    s.apply(Selection(pid: 20), placer: .fraction(0.9, on: .own), label: "90%")
    await waitUntil(4) { !s.isBusy }
    XCTAssertEqual(sys.frameOf(2)?.minX ?? 0, 1300, accuracy: 2, "restore finished after the move")
}

// ShepherdMoveTests
func testBulkMoveWaitsForSlowApp() async { /* listBehaviour .throwTimes(4), movePatience 1.5: moved, no alert "skipped" */ }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter "ShepherdRestoreTests|ShepherdMoveTests"`
Expected: FAIL (the restore gives up after 3 tries, and the interrupted restore is never resumed).

- [ ] **Step 3: Implement**

- `restore()` passes `patientUntil: Date(timeIntervalSince1970: book.changedAt + restoreTiming.patience)`. If that's in the past (a resumed or late pass), pass `nil`.
- Job deadline: `max(deadlineFor(windowCount:), patientUntil − now + 10)`.
- In its `done`, on `.interrupted` with an unchanged setup, set `resumeRestore = true`.
- `apply` bulk path passes `patientUntil: now + timing.movePatience`, with the same deadline rule. At the end of `finish`, if `resumeRestore`, clear it and call `schedulePass(after: 0.1)`.
- The single-window snap path is unchanged.
- Alerts pass `refused:` the count from `tally.refused`.

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: all pass. Existing restore tests may need `patience` set small in `make()`; that's the only allowed change to them.

- [ ] **Step 5: Commit**

`git commit -am "Restores wait up to 60 s for slow apps, bulk moves 30 s; an interrupted restore resumes"`

---

### Task 3: Retry row lasts until the next move or screen change

**Files:**
- Modify: `Sources/WindowShepherdCore/Engine/RetryOffer.swift`, `Sources/WindowShepherdCore/Engine/Shepherd.swift`
- Test: `Tests/WindowShepherdCoreTests/ShepherdMoveTests.swift`

**Interfaces:**
- Produces: `retryFor` removed. `retryRows()` no longer expires by time.

- [ ] **Step 1: Write the failing tests**

```swift
func testRetryOfferOutlivesTwoMinutes() async { /* make a move miss window 2; clock += 600; XCTAssertNotNil(s.retryRows()) */ }
func testNewMoveClearsRetryOffer() async { /* offer exists; s.apply(.everything, …); XCTAssertNil(s.retryOffer) right after apply starts */ }
```

- [ ] **Step 2: Run them to verify they fail.** Run: `swift test --filter ShepherdMoveTests`. Expected: FAIL.

- [ ] **Step 3: Implement.** Drop the time check in `retryRows()`. Clear `retryOffer` at the start of `apply` unless `sel.retry`. Screen changes already clear it. Update the RetryOffer doc comment ("until the next move or screen change").

- [ ] **Step 4: Run tests.** Run: `swift test`. Expected: all pass.

- [ ] **Step 5: Commit.** `git commit -am "Retry row lasts until the next move or screen change"`

---

### Task 4: Forget closed windows

**Files:**
- Modify: `Sources/WindowShepherdCore/Windows/WindowSystem.swift`, `Sources/WindowShepherdCore/Windows/CGWindow.swift`, `Sources/WindowShepherdCore/Windows/LiveWindowSystem.swift`, `Sources/WindowShepherdCore/Restore/LayoutBook.swift`, `Sources/WindowShepherdCore/Engine/Shepherd+Restore.swift`, `Tests/WindowShepherdCoreTests/FakeWindowSystem.swift`
- Test: `Tests/WindowShepherdCoreTests/LayoutBookTests.swift`, `Tests/WindowShepherdCoreTests/ShepherdRestoreTests.swift`

**Interfaces:**
- Produces:
  - `WindowSystem.allWindowIDs() -> Set<UInt32>` (*main*). CG `.optionAll` + `.excludeDesktopElements`, layer 0, any size; includes other Spaces and minimized windows.
  - `CGWindow.allIDs(excludingPID:)`.
  - `LayoutBook.forgetClosed(existing: Set<UInt32>, running: Set<pid_t>) -> Bool` (true if anything was dropped). It applies to `layouts` and, after Task 5, `frozen`.
  - Fake: `var closedIDs: Set<UInt32>`. `allWindowIDs()` returns the `windows` ids plus `offSpace` ids, minus `closedIDs`. Add `var offSpace: [CGWindow]` (exists but not visible).

- [ ] **Step 1: Write the failing tests**

```swift
func testForgetClosedDropsOnlyClosedWindowsOfRunningApps() {
    let b = book()
    let u = UnitRect(x: 0, y: 0, w: 1, h: 1)
    b.layouts[key] = ["1": LayoutEntry(pid: 10, app: "Chrome", scr: "UUID-2", unit: u, seen: 0),   // closed
                      "2": LayoutEntry(pid: 10, app: "Chrome", scr: "UUID-2", unit: u, seen: 0),   // other Space: exists
                      "3": LayoutEntry(pid: 30, app: "Quit", scr: "UUID-2", unit: u, seen: 0)]     // app not running: left to restorePlan
    XCTAssertTrue(b.forgetClosed(existing: [2], running: [10]))
    XCTAssertEqual(Set(b.layouts[key]!.keys), ["2", "3"])
}
func testRestorePlanCountsIgnoreClosedWindows() async { /* remembered id 9 closed (closedIDs = [9]): after replug, "restore plan:" counts 0 for it */ }
```

- [ ] **Step 2: Run them to verify they fail.** Run: `swift test --filter "LayoutBookTests|ShepherdRestoreTests"`. Expected: compile failure.

- [ ] **Step 3: Implement.** Call `forgetClosed` at the top of `restore()` (before `restorePlan`), and in `checkScreens` right before the existing save (when it saves). If it returns true, save.

- [ ] **Step 4: Run tests.** Run: `swift test`. Expected: all pass.

- [ ] **Step 5: Commit.** `git commit -am "Forget remembered windows that have closed"`

---

### Task 5: Frozen copies and left-behind tracking

**Files:**
- Create: `Sources/WindowShepherdCore/Restore/FrozenStore.swift`
- Modify: `Sources/WindowShepherdCore/Restore/LayoutBook.swift`, `Sources/WindowShepherdCore/Engine/Shepherd+Restore.swift`, `Sources/WindowShepherdCore/Engine/Shepherd.swift`
- Test: `Tests/WindowShepherdCoreTests/LayoutBookTests.swift`, `Tests/WindowShepherdCoreTests/ShepherdRestoreTests.swift`

**Interfaces:**
- Consumes: `forgetClosed` (Task 4).
- Produces:
  - `public struct FrozenCopy: Codable, Equatable { public var layout: [String: LayoutEntry]; public var at: Double }`
  - `LayoutBook.frozen: [String: FrozenCopy]`
  - `LayoutBook.leftBehind: Set<String>`
  - `LayoutBook.minActiveToFreeze: Double = 60`
  - `LayoutBook.setupChanged(to:now:)`: its existing signature, now also running the departure rule for `lastSetup`.
  - `LayoutBook.restoreFinished(plan:visible:)`: its existing parameters plus `visible: Set<String>`. Unmoved, visible → `leftBehind`.
  - `LayoutBook.resolve(windows: [CGWindow], screens: [ScreenInfo])`: drops `leftBehind` ids that are closed, at their live spot, or marked yours.
  - `LayoutBook.markYours(_ id: String)`: called wherever a window becomes the user's (the snapshot's protect-differs branch, `restorePlan`'s "moved by you" branch, `recordNow`).
  - `LayoutBook.unresolvedVisible(_ windows: [CGWindow]) -> Int`
  - `public final class FrozenStore`, mirroring `LayoutStore`: `url` (default `Application Support/Window Shepherd/frozen.json`), `load() -> FrozenState`, `save(_:)`, with atomic writes on a utility queue.
  - `public struct FrozenState: Codable, Equatable { var copies: [String: FrozenCopy]; var lastChangeKey: String?; var lastChangeAt: Double? }`
  - `Shepherd.init(..., frozenStore: FrozenStore = FrozenStore())`

- [ ] **Step 1: Write the failing tests**

```swift
// LayoutBookTests
func testDepartureFreezesAfterAMinute() {
    let b = book(); b.lastSetup = key; b.changedAt = 0
    b.layouts[key] = ["1": entry(scr: "UUID-2")]
    b.setupChanged(to: "OTHER", now: 61)
    XCTAssertEqual(b.frozen[key], FrozenCopy(layout: ["1": entry(scr: "UUID-2")], at: 61))
}
func testFlickerKeepsFrozenCopy() {
    let b = book(); b.lastSetup = key; b.changedAt = 100
    b.frozen[key] = FrozenCopy(layout: ["1": entry(scr: "UUID-2")], at: 50)
    b.layouts[key] = ["1": entry(scr: "UUID-1")]          // picked up a stranded spot
    b.setupChanged(to: "OTHER", now: 102)                 // active 2 s
    XCTAssertEqual(b.frozen[key]?.at, 50)
    XCTAssertEqual(b.layouts[key]?["1"]?.scr, "UUID-2", "live rolled back to the frozen copy")
}
func testUnresolvedLeftBehindKeepsFrozenCopy() { /* active 300 s, leftBehind = ["1"] → same expectations as flicker */ }
func testUserMoveResolvesLeftBehind() {
    let b = book(); b.leftBehind = ["1"]
    b.markYours("1")
    XCTAssertTrue(b.leftBehind.isEmpty)
}
func testResolveDropsArrivedAndClosed() { /* leftBehind ["1","2"]; window 1 now at its live spot, window 2 absent → empty */ }

// ShepherdRestoreTests
func testFrozenCopySurvivesRestart() async { /* freeze, make a new Shepherd on the same stores → book.frozen equal */ }
func testRestoreLeavesUnmovedVisibleWindowsLeftBehind() async { /* failSet = [1], patience small → book.leftBehind == ["1"] */ }
```

`entry(scr:)` is a small test helper returning `LayoutEntry(pid: 10, app: "Safari", scr:, unit: UnitRect(x: 0, y: 0, w: 0.5, h: 0.5), seen: 0)`.

- [ ] **Step 2: Run them to verify they fail.** Run: `swift test --filter "LayoutBookTests|ShepherdRestoreTests"`. Expected: compile failure.

- [ ] **Step 3: Implement**

Departure rule, in `setupChanged` before resetting state:

```swift
if let old = lastSetup, old != key {
    if now - changedAt >= minActiveToFreeze && leftBehind.isEmpty {
        frozen[old] = FrozenCopy(layout: layouts[old] ?? [:], at: now)
    } else if let f = frozen[old] {
        layouts[old] = f.layout
    }
}
leftBehind = []
```

Engine wiring:
- `checkScreens` calls `book.resolve` on every settled tick, before the snapshot.
- On a setup change, save `FrozenState` (copies, plus `lastChangeKey = key` and `lastChangeAt = now`).
- `start()` loads frozen copies into the book (the restart test).
- `restore()`'s `done` passes the visible ids to `restoreFinished`.
- `forgetClosed` also prunes `frozen`.

- [ ] **Step 4: Run tests.** Run: `swift test`. Expected: all pass.

- [ ] **Step 5: Commit.** `git commit -am "Frozen layout copy per screen combination, and left-behind tracking"`

---

### Task 6: Flashing icon and the Revert row

**Files:**
- Modify: `Sources/WindowShepherdCore/Engine/Shepherd.swift`, `Sources/WindowShepherdCore/Engine/Shepherd+Restore.swift`, `Sources/WindowShepherdCore/Menu/MenuModel.swift`, `App/WindowShepherd/StatusMenuController.swift`, `App/WindowShepherd/MenuBarGlyph.swift` (if needed), `App/WindowShepherd/AppDelegate.swift`
- Test: `Tests/WindowShepherdCoreTests/ShepherdRestoreTests.swift`, `Tests/WindowShepherdCoreTests/MenuModelTests.swift`

**Interfaces:**
- Consumes: `frozen`, `leftBehind`, `unresolvedVisible`, and `FrozenState.lastChangeKey` (Task 5).
- Produces:
  - `public struct RevertInfo: Equatable { public let label: String; public let at: Date; public let notWhere: Int }`
  - `Shepherd.revertInfo() -> RevertInfo?`: non-nil when `frozen[currentKey]` exists and `lastChangeKey == currentKey`. `notWhere` = visible windows in the copy whose spot differs (`Geometry.sameSpot`).
  - `Shepherd.revert()`: cancel pending passes and stop a running restore (`runner.stopCurrent(reportAs: nil)` only when `runner.current?.kind == .restore`). Then overwrite the live entries with the frozen copy's entries, then `restoreNow()`.
  - `Shepherd.flashing: Bool` (read-only outside), `Shepherd.onFlashChanged: ((Bool) -> Void)?`, `Shepherd.menuOpened()`.
  - `MenuAction.revert`, `MenuInputs.revert: RevertInfo?`
  - `MenuModel.revertTime(_ at: Date, now: Date) -> String`: `"h:mm a"`-style via `setLocalizedDateFormatFromTemplate("jmm")` on the same day, `"MMMd jmm"` otherwise.

- [ ] **Step 1: Write the failing tests**

```swift
// MenuModelTests
func testRevertRowsOnTop() {
    var i = inputs()
    let at = Date()
    i.revert = RevertInfo(label: "Built-in + DELL", at: at, notWhere: 32)
    let m = MenuModel.build(i)
    XCTAssertEqual(m[0], .item(title: "Revert Built-in + DELL", keys: nil, action: .revert))
    XCTAssertEqual(m[1], .item(title: "to how it was at \(MenuModel.revertTime(at, now: at)), before they were separated",
                               keys: nil, action: .revert, indent: 1))
    XCTAssertEqual(m[2], .item(title: "32 windows aren't where they were then", keys: nil, action: .revert, indent: 1))
}
func testRevertCountWording() { /* 1 → "1 window isn't where it was then"; 0 → "Every window is where it was then" */ }
func testNoRevertRowWithoutFrozenCopy() { /* inputs().revert == nil → first row isn't "Revert…" */ }

// ShepherdRestoreTests
func testLeftBehindFlashesUntilMenuOpens() async {
    let s = await rememberedThenUnplugged()           // patience small in make()
    sys.failSet = [1]
    sys.allScreens = [lap, dell]; s.tick()
    await waitUntil(4) { !s.isBusy }
    XCTAssertTrue(s.flashing)
    s.menuOpened()
    XCTAssertFalse(s.flashing)
}
func testFlashStopsWhenLeftBehindResolves() async { /* flashing; user moves window 1 (recordNow via apply) → tick → false */ }
func testRevertPutsBackFrozenSpots() async { /* freeze with 1 on DELL; replug; move 1 to built-in by hand + tick twice; s.revert(); window 1 back on DELL */ }
func testRevertCancelsRunningRestore() async { /* setDelay so restore runs; revert(); runner shows a fresh restore and window ends at frozen spot */ }
```

- [ ] **Step 2: Run them to verify they fail.** Run: `swift test --filter "MenuModelTests|ShepherdRestoreTests"`. Expected: compile failure.

- [ ] **Step 3: Implement**

Engine:
- Set `flashing = true` when a restore job finishes with `pendingPasses == 0` and `book.unresolvedVisible(visible) > 0`.
- Set it false on `menuOpened()`, on a setup change, or on a tick where `unresolvedVisible == 0`.
- Fire `onFlashChanged` only when it changes.

Menu:
- `MenuModel.build` puts the three Revert rows first, then a separator, above the retry rows.
- The row text uses the copy in Global Constraints.

App:
- `StatusMenuController.setFlashing(_:)` runs a 0.5 s repeating `Timer` that alternates `MenuBarGlyph.image(busy: true)` and `image(busy: false)`.
- When `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is on, it shows `busy: true` steadily instead.
- While busy, the busy image wins.
- `menuWillOpen` calls `shepherd.menuOpened()`.
- `menuNeedsUpdate` passes `inputs.revert = s.revertInfo()`.
- `AppDelegate` wires `onFlashChanged` and maps `.revert` to `shepherd.revert()`.

- [ ] **Step 4: Run tests and build the app.** Run: `swift test`, then `scripts/build.sh Debug`. Expected: all pass; build succeeds.

- [ ] **Step 5: Commit.** `git commit -am "Flash the icon when windows are left behind; Revert row puts back the frozen copy"`

---

### Task 7: Windows opened while undocked

**Files:**
- Create: `Sources/WindowShepherdCore/Restore/UndockedWindows.swift`, `App/WindowShepherd/UndockedStore.swift`
- Modify: `Sources/WindowShepherdCore/Geometry/Screens.swift`, `Sources/WindowShepherdCore/Restore/LayoutBook.swift`, `Sources/WindowShepherdCore/Engine/Shepherd+Restore.swift`, `App/WindowShepherd/Settings/SettingsView.swift`, `App/WindowShepherd/Settings/SettingsModel.swift`, `App/WindowShepherd/AppDelegate.swift`
- Test: create `Tests/WindowShepherdCoreTests/UndockedTests.swift`

**Interfaces:**
- Produces:
  - ```swift
    public struct UndockedWindows: Codable, Equatable {
        public enum Target: Codable, Equatable { case biggest, named(uuid: String, name: String) }
        public enum Size: String, Codable, CaseIterable { case ninety = "90% centered", full = "Full screen", sixty = "60% centered", keep = "Same size, centered" }
        public var enabled = true; public var target = Target.biggest; public var size = Size.ninety
        public static let defaults = UndockedWindows()
        public func screen(in screens: [ScreenInfo]) -> ScreenInfo?
    }
    ```
    `screen(in:)` returns the named screen if connected, else `Screens.biggest`.
  - `Screens.biggest(_ screens: [ScreenInfo]) -> ScreenInfo?`: the largest `full` area; ties go to the non-built-in, then the first.
  - `RestoreTarget.keepSize: Bool = false`: when true, the action centers the window at its own size on `screenUUID`.
  - `LayoutBook.homeless: Set<String>`: set at a setup change that **adds** a screen. It holds visible ids with no entry in `layouts[newKey]` or `frozen[newKey]`.
  - `Shepherd.undocked: UndockedWindows` (set by the app).
  - App: `UndockedStore` stores UserDefaults key `"undockedWindows"` as JSON. When nothing is stored, it returns `.defaults`.

- [ ] **Step 1: Write the failing tests**

```swift
func testBiggestScreen() { /* 1000×800 built-in, 2560×1440 DELL → DELL */ }
func testNamedScreenMissingFallsBackToBiggest() {
    let u = UndockedWindows(enabled: true, target: .named(uuid: "GONE", name: "LG"), size: .ninety)
    XCTAssertEqual(u.screen(in: [lap, dell])?.uuid, dell.uuid)
}
func testWindowOpenedWhileUndockedGoesToBiggestAt90() async {
    // remembered layout exists for [lap, dell]; unplug; addApp(30, "Safari", windows: [(7, rect(40))]); tick twice; replug
    // → window 7 frame == Geometry.place(UnitRect(x: 0.05, y: 0.05, w: 0.9, h: 0.9), in: dell.frame)
}
func testUndockedOffLeavesThem() async { /* s.undocked.enabled = false → window 7 unmoved */ }
func testOnlyWhenAScreenIsAdded() async { /* unplugging never moves homeless windows; windows opened while docked never move */ }
func testKeepSizeCenters() async { /* size .keep → window 7 same size, centered on dell.frame */ }
```

- [ ] **Step 2: Run them to verify they fail.** Run: `swift test --filter UndockedTests`. Expected: compile failure.

- [ ] **Step 3: Implement**

Engine:
- In `checkScreens`, on a setup change, compute `homeless` before `setupChanged` (it needs the new key and the visible windows), but only if the new screen uuids aren't a subset of the old ones.
- In `restore()`, after `restorePlan`, add each visible `homeless` id not in `restoredIds` to the plan. Size units: `.ninety` → `UnitRect(x: 0.05, y: 0.05, w: 0.9, h: 0.9)`, `.full` → `(0, 0, 1, 1)`, `.sixty` → `(0.2, 0.2, 0.6, 0.6)`, `.keep` → `keepSize: true`.
- Remove ids from `homeless` once moved.

App:
- New section in `SettingsView`, after "Send to a screen", titled **"Windows opened while undocked"**. Intro: "When you plug in a screen, windows you opened without it go here. Windows that already have a place go back to it."
- Controls:
  - a Toggle
  - a screen Picker: "The biggest screen", then each connected screen by name, plus the saved named screen if it isn't connected, labeled "<name> (not connected)" in full-strength text
  - a size Picker using `Size.rawValue`
- Changes save through `UndockedStore` and set `shepherd.undocked` at once.
- Load at launch in `AppDelegate`.

- [ ] **Step 4: Run tests, build, snapshot.** Run: `swift test`, then `scripts/build.sh Debug`. Then `open -n "<Debug app>" --args -WSOpenSettings YES -WSSnapshotSettings $SCRATCH/settings.png`. Read the PNG and check that the new section shows with no grey text. Quit that copy.

- [ ] **Step 5: Commit.** `git commit -am "Windows opened while undocked go to a chosen screen when you plug in (default: biggest, 90%)"`

---

### Task 8: Docs and live check

**Files:**
- Modify: `README.md` (restore / retry wording), `docs/website/content.md` (any claim about retry timing or restore behavior), `PRIVACY.md` (add `frozen.json` to the stored-data list if the file lists `layouts.json`)

- [ ] **Step 1: Find every place that needs updating.** Run: `grep -n -i -e "two minutes" -e "2 minutes" -e "retry" -e "layouts.json" -e "restore" README.md PRIVACY.md docs/website/content.md`. Update each hit to the new behavior: patience, Revert, flashing icon, the undocked setting, `frozen.json`.
- [ ] **Step 2: Full test run.** Run: `swift test`. Expected: all pass, 0 failures.
- [ ] **Step 3: Commit and push.** `git commit -am "Docs: patience, Revert, windows opened while undocked"` and `git push`.
- [ ] **Step 4: Live check with Charles.** Run `scripts/run-dev.sh`, and ask Charles to:
  1. set the undocked setting to DELL U2718Q, 90% centered
  2. unplug for a while, open a few windows, and replug
  3. report what he sees

  Then read the log. Expected:
  - The restore waits through "not responding" without "skipped … after 3 tries".
  - New windows land on the Dell at 90%.
  - If anything is left behind, the icon flashes and the Revert row names "Built-in Retina Display + DELL U2718Q".
