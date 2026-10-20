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
            book.setupChanged(to: key, now: nowSeconds)
            retryOffer = nil   // its targets were for the old setup
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
            let changed = book.snapshot(key: key, windows: system.visibleWindows(), screens: screens, now: nowSeconds)
            if changed || Date().timeIntervalSince1970 - store.lastSaved > 600 { store.save(book.layouts) }
        }
    }

    func schedulePass(after delay: TimeInterval) {
        pendingPasses += 1
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.restorePass()
        }
        restoreTimers.append(task)
    }

    func cancelRestores() {
        for t in restoreTimers { t.cancel() }
        restoreTimers = []
        pendingPasses = 0
    }

    /// A scheduled pass: restore, then let the icon drop its red once nothing is left.
    func restorePass() {
        pendingPasses = max(0, pendingPasses - 1)
        restore()
        updateBusy()
    }

    func restore() {
        let screens = system.screens()
        let key = Screens.setupKey(screens)
        guard book.layouts[key] != nil else { book.settled = true; return }
        if runner.current != nil {   // an earlier pass, or your own move, is still running: check again shortly
            schedulePass(after: restoreTiming.busyRecheck)
            return
        }
        let running = Set(system.runningApps().keys)
        guard let plan = book.restorePlan(key: key, windows: system.visibleWindows(), screens: screens, running: running),
              !plan.isEmpty else {
            book.settled = true
            offerRetry(.restore, missed: [:]) { _ in }   // nothing left to put back
            return
        }
        let main = system.mainScreen()
        let tally = Tally<RestoreTarget>()
        let steps: [JobStep] = plan.keys.sorted().map { pid in
            appStep(pid: pid, wanted: plan[pid]!, system: system, worker: jobWorker, timing: timing, tally: tally,
                    action: { win, t in
                        let placer = Placer.unit(t.unit, .fixed(uuid: t.screenUUID), fitInside: true)
                        guard let r = placer.frame(for: win.frame() ?? .zero, screens: screens, main: main) else {
                            throw AXFailure(code: -25200)
                        }
                        try win.setFrame(r)
                    },
                    onMoved: { [weak self] _, t in self?.book.restoredIds.insert(t.id) })   // later passes won't touch it again
        }
        let label = Screens.setupLabel(screens)
        let count = plan.values.reduce(0) { $0 + $1.count }
        runner.run(.restore, steps: steps, deadline: deadlineFor(windowCount: count)) { [weak self] problem in
            guard let self else { return }
            tally.settle()
            let total = tally.moved
            self.book.restoreFinished(plan: plan)
            self.book.settled = true                // snapshots may resume; missed windows stay protected
            if self.pendingPasses > 0 {             // the next pass retries skipped windows itself: don't announce them yet
                tally.skipped = []
                tally.missed = [:]
            }
            if problem != .interrupted {            // missed windows aren't in restoredIds, so restore() retries just them
                self.offerRetry(.restore, missed: tally.missed.mapValues { Set($0.keys) }) { [weak self] _ in self?.restore() }
            }
            Log.info("restored \(total) windows for \(label)" + (problem.map { " (\($0))" } ?? ""))
            if total > 0 || !tally.skipped.isEmpty || problem != nil {
                self.alert(reportText("Restored \(total) window\(total == 1 ? "" : "s") for this screen setup",
                                      skipped: tally.skipped, hasMissed: !tally.missed.isEmpty, problem: problem))
            }
        }
    }
}
