import Foundation

/// Auto-restore, per screen setup. For each combination of connected screens
/// ("laptop only", "laptop + Dell") remember where every window sits; when
/// the setup changes, in either direction, put each window back where it was
/// the last time that setup was active.
extension Shepherd {
    /// The 2 s timer. Cheap: the fast window list only.
    public func tick() {
        guard !paused else { return }
        // Safety net: a job that outlived its own deadline is stale; clear it
        // so it can't pause snapshots (and so auto-restore) forever.
        runner.clearIfStale(now: now())
        if runner.current?.kind != .place { releasePlacing() }   // cleared as stale: its `done` never runs
        checkScreens()
        spotsTick()
        updateBusy()
    }

    /// The screens changed (macOS told us). The 2 s tick catches the change
    /// anyway if this is missed, e.g. while asleep.
    public func screensChanged() {
        guard !paused else { return }
        checkScreens()
    }

    /// Put everything back for the current setup (testing and wsctl).
    public func restoreNow() {
        book.restoredIds = []
        restore()
    }

    /// Level-triggered: compares the current setup with the last one seen,
    /// so a missed screen event can't break auto-restore.
    func checkScreens() {
        let screens = system.screens()
        let key = Screens.setupKey(screens)
        if key != book.lastSetup {
            releasePlacing()   // a placement for the old setup is about to be stopped without its `done`
            let first = restoreTiming.passes.first ?? 0
            Log.info("screen setup is now \(Screens.setupLabel(screens)); \(book.layouts[key]?.count ?? 0) windows remembered for it, restoring in \(Int(first.rounded()))s")
            let before = Set(book.lastSetup?.split(separator: "+").map(String.init) ?? [])
            book.setupChanged(to: key, now: nowSeconds)   // freezes the old combination, or rolls it back
            if !Set(screens.map(\.uuid)).isSubset(of: before) {   // a screen was added
                let home = book.layouts[key] ?? [:], frozen = book.frozen[key]?.layout ?? [:]
                book.homeless = Set(system.visibleWindows().map { String($0.id) }.filter { home[$0] == nil && frozen[$0] == nil })
            }
            lastChange = (key, nowSeconds)
            frozenStore.save(FrozenState(copies: book.frozen, lastChangeKey: key, lastChangeAt: nowSeconds))
            store.save(book.layouts)
            retryOffer = nil   // its targets were for the old setup
            for id in firstSeen.keys { leaveFirstSeen(id) }   // macOS is moving windows now: the restore's job
            setFlashing(false)
            resumeRestore = false   // that restore was for the old setup
            if let job = runner.current {   // it was moving/restoring for the old setup: stop it
                Log.info("stopped a \(job.kind.rawValue) that was running for the previous screen setup")
                runner.stopCurrent(reportAs: nil)
            }
            // Let macOS finish rearranging, then restore; the later passes catch
            // apps that were still busy (Safari, Finder) right after the change.
            cancelRestores()
            for delay in restoreTiming.passes { schedulePass(after: delay) }
            updateBusy()
            return
        }
        // Don't snapshot while windows are still being put back (or moved), or
        // half-moved positions would be recorded. Never stay unsettled for long.
        if !book.settled && nowSeconds - book.changedAt > restoreTiming.unsettledLimit { book.settled = true }
        guard book.settled && runner.current == nil else {
            snapshotTimes = []   // a gap in the snapshots: a move seen after it can't be timed against the mouse
            if book.settled {    // new windows are still sighted while a job runs; placing them waits for it
                let visible = system.visibleWindows()
                requestKinds(visible)
                placeNewWindows(visible: visible, screens: screens, key: key)
            }
            return
        }
        let shown = system.visibleWindows()
        defer { lastTickWindows = shown }
        if !book.offscreen.isEmpty {
            if nowSeconds - book.changedAt > restoreTiming.offscreenFor {
                book.offscreen = []   // too long after the change: it's just a window you opened
            } else {
                book.dropTabSwitches(shown: shown, previous: lastTickWindows)
            }
        }
        // A window that was on another Space during the restore just showed
        // up where macOS left it: put it back now (and don't record that spot).
        if book.offscreenVisible(shown) {
            snapshotTimes = []
            restore()
            return
        }
        let visible = system.visibleWindows()
        book.visibleAtLastTick = Set(visible.map { String($0.id) })
        if !book.leftBehind.isEmpty {
            book.resolve(windows: visible, screens: screens, existing: system.allWindowIDs())
        }
        if flashing && book.unresolvedVisible(visible) == 0 { setFlashing(false) }
        checkLandings(visible: visible, screens: screens, key: key)
        requestKinds(visible)
        placeNewWindows(visible: visible, screens: screens, key: key)
        // A window whose move isn't checked yet isn't recorded where it is.
        let unchecked = landing.pending()
        let snap = book.snapshot(key: key, windows: unchecked.isEmpty ? visible : visible.filter { !unchecked.contains($0.id) },
                                 screens: screens, now: nowSeconds)
        recordMoves(snap.moved, windows: visible, key: key, screens: screens)
        recordDraggedNew(visible, key: key, screens: screens)
        noteSnapshot()
        spots.touch(key: key, visible: book.visibleAtLastTick, now: nowSeconds)
        if snap.changed || Date().timeIntervalSince1970 - store.lastSaved > 600 {
            let existing = system.allWindowIDs()
            book.forgetClosed(existing: existing, running: Set(system.runningApps().keys))
            forgetKinds()
            forgetSpots(existing: existing)
            forgetNewWindows(existing: existing)
            store.save(book.layouts)
        }
    }

    /// Visible main windows with no per-window entry for this setup (and not put back
    /// or placed by you since the change) go to a free spot for their app. Each app's
    /// windows are matched to its spots by `AppSpotBook.assign`; the hold is taken only
    /// once a window is in its spot (`onMoved`), so a move that fails frees it again.
    /// A window already sitting in the spot it's given just holds it. Returns window id → spot id.
    func addAppSpots(to plan: inout [pid_t: [UInt32: RestoreTarget]]?, windows: [CGWindow], screens: [ScreenInfo],
                     key: String) -> [String: String] {
        guard let byApp = spots.spots[key], !byApp.isEmpty else { return [:] }
        let layout = book.layouts[key] ?? [:]
        let connected = Set(screens.map(\.uuid))
        var byBundle: [String: [CGWindow]] = [:]
        for w in windows {
            let id = String(w.id)
            // An unknown kind waits for a later pass; a window that holds a spot is in it, or being placed.
            guard layout[id] == nil, !book.restoredIds.contains(id), isMainWindow(id) == true,
                  !spots.holds(key: key, window: id), plan?[w.pid]?[w.id] == nil,
                  let bundle = system.bundleID(pid: w.pid), byApp[bundle]?.isEmpty == false else { continue }
            byBundle[bundle, default: []].append(w)
        }
        var spotFor: [String: String] = [:]
        for (bundle, ws) in byBundle.sorted(by: { $0.key < $1.key }) {
            let got = spots.assign(key: key, bundle: bundle, windows: ws.map { (String($0.id), Geometry.whereIs($0.frame, in: screens)) },
                                   now: nowSeconds)
            for w in ws {
                let id = String(w.id)
                guard let spot = got[id] else { continue }   // more windows than free spots: left where they are
                let at = Geometry.whereIs(w.frame, in: screens)
                if Geometry.sameSpot(at, spot.spot) {          // already there: nothing to move
                    book.restoredIds.insert(id)
                    book.homeless.remove(id)                   // its app's spot came first: never the undocked default
                    continue
                }
                spots.holders[key]?[id] = nil                  // held once it's in the spot
                guard connected.contains(spot.scr) else { continue }
                var t = RestoreTarget(id: id, screenUUID: spot.scr, unit: spot.unit, from: at)
                t.fromAppSpot = true
                plan = plan ?? [:]
                plan![w.pid, default: [:]][w.id] = t
                spotFor[id] = spot.id
            }
        }
        if !byBundle.isEmpty { spotsDirty = true }   // `assign` refreshed the spots' last-used times
        return spotFor
    }

    /// Windows opened while a screen was unplugged go where the undocked setting says,
    /// unless their app had a spot for them (already in `plan`).
    func addHomeless(to plan: inout [pid_t: [UInt32: RestoreTarget]]?, windows: [CGWindow], screens: [ScreenInfo]) {
        guard undocked.enabled, !book.homeless.isEmpty, let target = undocked.screen(in: screens) else { return }
        let unit = undocked.size.unit
        var n = 0
        defer { if n > 0 { Log.info("\(n) window\(n == 1 ? "" : "s") opened while undocked → \(target.name) (\(undocked.size.rawValue))") } }
        for w in windows where book.homeless.contains(String(w.id)) && !book.restoredIds.contains(String(w.id))
            && plan?[w.pid]?[w.id] == nil {
            var t = RestoreTarget(id: String(w.id), screenUUID: target.uuid, unit: unit ?? UnitRect(x: 0, y: 0, w: 1, h: 1),
                                  from: Geometry.whereIs(w.frame, in: screens))
            t.keepSize = unit == nil
            plan = plan ?? [:]
            plan![w.pid, default: [:]][w.id] = t
            n += 1
        }
    }

    func schedulePass(after delay: TimeInterval) {
        pendingPasses += 1
        nextTimerID += 1
        let id = nextTimerID
        restoreTimers[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.restoreTimers[id] = nil
            self.restorePass()
        }
    }

    func cancelRestores() {
        for t in restoreTimers.values { t.cancel() }
        restoreTimers = [:]
        pendingPasses = 0
    }

    /// A scheduled pass: restore, then let the icon drop its red once nothing is left.
    func restorePass() {
        pendingPasses = max(0, pendingPasses - 1)
        restore()
        updateBusy()
    }

    /// `patience`: seconds to keep retrying from now; nil = what's left since the screen change.
    /// `recordsSpots`: every window it moves becomes an app spot (Revert: your choice of
    /// arrangement); later passes and the Retry row don't inherit it.
    func restore(patience: TimeInterval? = nil, recordsSpots: Bool = false) {
        let screens = system.screens()
        let key = Screens.setupKey(screens)
        guard book.layouts[key] != nil || !book.homeless.isEmpty || spots.spots[key]?.isEmpty == false else {
            book.settled = true
            return
        }
        if runner.current != nil {   // an earlier pass, or your own move, is still running: check again shortly
            schedulePass(after: restoreTiming.busyRecheck)
            return
        }
        let running = Set(system.runningApps().keys)
        let existing = system.allWindowIDs()
        if book.forgetClosed(existing: existing, running: running) { store.save(book.layouts) }
        forgetKinds()
        forgetSpots(existing: existing)
        forgetNewWindows(existing: existing)
        let visibleNow = system.visibleWindows()
        var plan = book.restorePlan(key: key, windows: visibleNow, screens: screens, running: running)
        Log.info("restore plan: \(book.planCounts.summary)")
        // Precedence: its own entry, then a free spot for its app, then the undocked default.
        // Revert replays the frozen copy only.
        let spotFor = recordsSpots ? [:] : addAppSpots(to: &plan, windows: visibleNow, screens: screens, key: key)
        addHomeless(to: &plan, windows: visibleNow, screens: screens)
        guard let plan, !plan.isEmpty else {
            book.settled = true
            offerRetry(.restore, missed: [:]) { _ in }   // nothing left to put back
            return
        }
        let main = system.mainScreen()
        let tally = Tally<RestoreTarget>()
        let apps = Dictionary(visibleNow.map { ($0.id, $0.app) }, uniquingKeysWith: { a, _ in a })
        // Patience runs from the screen change, so a resumed or late pass gets only what's left.
        let remaining = patience ?? (book.changedAt + restoreTiming.patience - nowSeconds)
        let patientUntil = remaining > 0 ? Date().addingTimeInterval(remaining) : nil
        // A patient job does the later passes' work itself: drop them, or they'd run after it, past the budget.
        if patientUntil != nil { cancelRestores() }
        let plannedAt = Date()
        let landing = self.landing, clock = landingClock
        let steps: [JobStep] = plan.keys.sorted().map { pid in
            appStep(pid: pid, wanted: plan[pid]!, system: system, worker: jobWorker, timing: timing, tally: tally,
                    patientUntil: patientUntil,
                    gate: { [weak self] in self?.book.lastSetup == key },
                    skip: { [weak self] id in
                        self?.placedByYou(id, from: plan[pid]?[id]?.from, plannedAt: plannedAt, screens: screens) ?? true
                    },
                    action: Self.targetAction(screens: screens, main: main, pid: pid, landing: landing, clock: clock) { _, _ in .restore },
                    onMoved: { [weak self] id, t in               // later passes won't touch it again
                        guard let self else { return }
                        self.book.restoredIds.insert(t.id)
                        let name = screens.first { $0.uuid == t.screenUUID }?.name ?? t.screenUUID
                        let app = apps[id] ?? "?"
                        if t.fromAppSpot {   // in its app's spot: it holds it now, and the spot is refreshed, not added
                            self.book.homeless.remove(t.id)
                            if let spot = spotFor[t.id] {
                                self.spots.holders[key, default: [:]][t.id] = spot
                                self.heldByRestore[t.id] = self.nowSeconds
                                self.spots.touch(key: key, visible: [t.id], now: self.nowSeconds)
                                self.spotsDirty = true
                            }
                            Log.info("\(app) window \(id) → its spot on \(name) (\(Self.unitLabel(t.unit))), no memory for this screen setup")
                            return
                        }
                        // Revert, and the undocked default (your own setting placing it), count as spots;
                        // a plain restore to its own per-window entry records nothing.
                        let homeless = self.book.homeless.remove(t.id) != nil
                        if homeless {
                            let size = t.keepSize ? UndockedWindows.Size.keep.rawValue : Self.unitLabel(t.unit)
                            Log.info("\(app) window \(id) → \(name) (\(size)), opened while undocked")
                        }
                        if homeless || recordsSpots,
                           let w = self.system.visibleWindows().first(where: { String($0.id) == t.id }) {
                            self.recordSpot(w, key: key, screens: screens)
                        }
                    })
        }
        let label = Screens.setupLabel(screens)
        let count = plan.values.reduce(0) { $0 + $1.count }
        runner.run(.restore, steps: steps, deadline: max(deadlineFor(windowCount: count), remaining + 10)) { [weak self] problem in
            guard let self else { return }
            tally.settle()
            let total = tally.moved
            var refused = tally.refused.values.reduce(0) { $0 + $1.count }
            if problem == .interrupted && self.book.lastSetup == key {
                self.resumeRestore = true           // your move came first; the restore picks up after it
            }
            let visible = self.system.visibleWindows()
            self.book.restoreFinished(plan: plan, visible: Set(visible.map { String($0.id) }))
            if self.pendingPasses == 0 && problem != .interrupted && self.book.unresolvedVisible(visible) > 0 {
                self.setFlashing(true)              // done trying, and some didn't make it
            }
            self.book.settled = true                // snapshots may resume; missed windows stay protected
            if self.pendingPasses > 0 {             // the next pass retries skipped windows itself: don't announce them yet
                tally.skipped = []
                tally.missed = [:]
                refused = 0
            }
            if problem != .interrupted {            // missed windows aren't in restoredIds, so restore() retries just them
                self.offerRetry(.restore, missed: tally.missed.mapValues { Set($0.keys) }, retry: .restore) { [weak self] _ in
                    self?.restore()
                }
            }
            Log.info("restored \(total) windows for \(label)" + (problem.map { " (\($0))" } ?? ""))
            if total > 0 || !tally.skipped.isEmpty || problem != nil || refused > 0 {
                self.alert(reportText("Restored \(total) window\(total == 1 ? "" : "s") for this screen setup",
                                      skipped: tally.skipped, hasMissed: !tally.missed.isEmpty, problem: problem, refused: refused))
            }
        }
    }

    /// Just before a restore or placement moves a window: true if you placed it
    /// since the plan was made, so it's yours now and stays where it is.
    func placedByYou(_ id: UInt32, from: Spot?, plannedAt: Date, screens: [ScreenInfo]) -> Bool {
        if book.restoredIds.contains(String(id)) { return true }   // a hotkey or menu move while the job ran
        // Dragged since the plan was made (no snapshot runs during a job): yours now.
        // Moved with no mouse use since then: macOS or the app moved it (after a wake or
        // an unplug they do, for a while), so it still goes (live 2026-10-29).
        guard let from, let w = system.visibleWindows().first(where: { $0.id == id }),
              !Geometry.sameSpot(Geometry.whereIs(w.frame, in: screens), from) else { return false }
        guard let used = system.lastMouseUse(), used > plannedAt else {
            Log.info("\(w.app) window \(id) moved since the plan with no mouse use: putting it back")
            return false
        }
        Log.info("\(w.app) window \(id) dragged since the plan: left there")
        book.restoredIds.insert(String(id))
        book.protect[String(id)] = nil
        book.markYours(String(id))
        return true
    }

    /// Moves a window to its target's fixed screen: the unit (fitted inside), or
    /// centred at its own size, and notes what it asked for (`retry`: how the Retry
    /// row tries it again if it doesn't land). Runs on the worker.
    nonisolated static func targetAction(screens: [ScreenInfo], main: ScreenInfo?, pid: pid_t, landing: Landing,
                                         clock: @escaping () -> Double,
                                         retry: @escaping (Placer, RestoreTarget) -> Landing.Retry)
        -> (WindowHandle, RestoreTarget) throws -> Void {
        return { win, t in
            let placer = t.keepSize ? Placer.center(.fixed(uuid: t.screenUUID))
                                    : Placer.unit(t.unit, .fixed(uuid: t.screenUUID), fitInside: true)
            // A fixed-screen unit needs no frame from the app; centring keeps the window's size.
            var current = CGRect.zero
            if t.keepSize {   // no size to keep if the app didn't answer: retry, never shrink it
                guard let f = win.frame() else { throw AXFailure(code: -25200) }
                current = f
            }
            guard let r = placer.frame(for: current, screens: screens, main: main) else {
                throw AXFailure(code: -25200)
            }
            try win.setFrame(r)
            guard let id = UInt32(t.id) else { return }
            landing.expect(.init(pid: pid, id: id, wanted: r, resizable: win.isResizable, at: clock(), retry: retry(placer, t)))
        }
    }
}
