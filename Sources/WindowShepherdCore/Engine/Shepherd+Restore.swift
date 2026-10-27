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
        checkScreens()
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
            let first = restoreTiming.passes.first ?? 0
            Log.info("screen setup is now \(Screens.setupLabel(screens)); \(book.layouts[key]?.count ?? 0) windows remembered for it, restoring in \(Int(first.rounded()))s")
            book.setupChanged(to: key, now: nowSeconds)   // freezes the old combination, or rolls it back
            lastChange = (key, nowSeconds)
            frozenStore.save(FrozenState(copies: book.frozen, lastChangeKey: key, lastChangeAt: nowSeconds))
            store.save(book.layouts)
            retryOffer = nil   // its targets were for the old setup
            setFlashing(false)
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
        if book.settled && runner.current == nil {
            // A window that was on another Space during the restore just showed
            // up where macOS left it: put it back now (and don't record that spot).
            if book.offscreenVisible(system.visibleWindows()) {
                restore()
                return
            }
            let visible = system.visibleWindows()
            if !book.leftBehind.isEmpty {
                book.resolve(windows: visible, screens: screens, existing: system.allWindowIDs())
            }
            if flashing && book.unresolvedVisible(visible) == 0 { setFlashing(false) }
            let changed = book.snapshot(key: key, windows: visible, screens: screens, now: nowSeconds)
            if changed || Date().timeIntervalSince1970 - store.lastSaved > 600 {
                book.forgetClosed(existing: system.allWindowIDs(), running: Set(system.runningApps().keys))
                store.save(book.layouts)
            }
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
    func restore(patience: TimeInterval? = nil) {
        let screens = system.screens()
        let key = Screens.setupKey(screens)
        guard book.layouts[key] != nil else { book.settled = true; return }
        if runner.current != nil {   // an earlier pass, or your own move, is still running: check again shortly
            schedulePass(after: restoreTiming.busyRecheck)
            return
        }
        let running = Set(system.runningApps().keys)
        if book.forgetClosed(existing: system.allWindowIDs(), running: running) { store.save(book.layouts) }
        let plan = book.restorePlan(key: key, windows: system.visibleWindows(), screens: screens, running: running)
        Log.info("restore plan: \(book.planCounts.summary)")
        guard let plan, !plan.isEmpty else {
            book.settled = true
            offerRetry(.restore, missed: [:]) { _ in }   // nothing left to put back
            return
        }
        let main = system.mainScreen()
        let tally = Tally<RestoreTarget>()
        // Patience runs from the screen change, so a resumed or late pass gets only what's left.
        let remaining = patience ?? (book.changedAt + restoreTiming.patience - nowSeconds)
        let patientUntil = remaining > 0 ? Date().addingTimeInterval(remaining) : nil
        let steps: [JobStep] = plan.keys.sorted().map { pid in
            appStep(pid: pid, wanted: plan[pid]!, system: system, worker: jobWorker, timing: timing, tally: tally,
                    patientUntil: patientUntil,
                    gate: { [weak self] in self?.book.lastSetup == key },
                    // You placed it while this job ran (a snap): it's yours now.
                    skip: { [weak self] id in self?.book.restoredIds.contains(String(id)) ?? true },
                    action: { win, t in
                        let placer = Placer.unit(t.unit, .fixed(uuid: t.screenUUID), fitInside: true)
                        guard let r = placer.frame(for: .zero, screens: screens, main: main) else {   // a fixed-screen unit: no need to ask the app
                            throw AXFailure(code: -25200)
                        }
                        try win.setFrame(r)
                    },
                    onMoved: { [weak self] _, t in self?.book.restoredIds.insert(t.id) })   // later passes won't touch it again
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
                self.offerRetry(.restore, missed: tally.missed.mapValues { Set($0.keys) }) { [weak self] _ in self?.restore() }
            }
            Log.info("restored \(total) windows for \(label)" + (problem.map { " (\($0))" } ?? ""))
            if total > 0 || !tally.skipped.isEmpty || problem != nil || refused > 0 {
                self.alert(reportText("Restored \(total) window\(total == 1 ? "" : "s") for this screen setup",
                                      skipped: tally.skipped, hasMissed: !tally.missed.isEmpty, problem: problem, refused: refused))
            }
        }
    }
}
