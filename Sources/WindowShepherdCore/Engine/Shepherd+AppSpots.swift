import Foundation

/// App spots learn only from placements that were yours or Window Shepherd's,
/// never from where an app or macOS put a window by itself.
extension Shepherd {
    /// How long a window's spot before its latest record is kept.
    static let lastRecordedFor: Double = 10

    /// The Mac woke from sleep: for a while, windows that move are macOS's doing.
    public func didWake() { wokeAt = nowSeconds }

    /// Shortly after the app launched, a screen change or a wake, a window that
    /// moves is likely macOS's or the app's guess, not yours. Cheap: no app calls.
    func inGuessingPeriod(pid: pid_t) -> Bool {
        let period = restoreTiming.guessing
        if let launched = system.launchDate(pid: pid), now().timeIntervalSince(launched) < period { return true }
        if nowSeconds - book.changedAt < period { return true }
        if let wokeAt, nowSeconds - wokeAt < period { return true }
        return false
    }

    /// A confirmed placement: the window's app spot moves here (or a new one is
    /// added). Main windows only; one whose kind isn't known yet is skipped, and
    /// its next confirmed move records it.
    func recordSpot(_ w: CGWindow, key: String, screens: [ScreenInfo]) {
        let id = String(w.id)
        guard isMainWindow(id) == true, let bundle = system.bundleID(pid: w.pid),
              let spot = Geometry.whereIs(w.frame, in: screens) else { return }
        if placing?.key == key { releasePlacing(id) }   // a spot it was given but never sat in isn't its own
        let held = spots.holders[key]?[id].flatMap { h in spots.spots[key]?[bundle]?.first { $0.id == h } }
        lastRecorded[id] = (held, nowSeconds)
        spots.record(key: key, bundle: bundle, window: id, at: spot, now: nowSeconds)
        spotsDirty = true
    }

    /// Windows whose confirmed spot changed at this snapshot: yours, unless it's
    /// a guessing period and the mouse wasn't used since the move began.
    func recordMoves(_ moved: Set<String>, windows: [CGWindow], key: String, screens: [ScreenInfo]) {
        guard !moved.isEmpty else { return }
        // Two sightings: the new spot was first seen at the previous snapshot,
        // so the move happened after the one before that.
        let mouse = system.lastMouseUse()
        let dragged = snapshotTimes.count == 2 && mouse.map { $0 > snapshotTimes[0] } == true
        for w in windows where moved.contains(String(w.id)) && (dragged || !inGuessingPeriod(pid: w.pid)) {
            recordSpot(w, key: key, screens: screens)
        }
    }

    /// A settled snapshot just ran.
    func noteSnapshot() {
        snapshotTimes = Array((snapshotTimes + [Date()]).suffix(2))
    }

    /// Closed windows free their spots; spots unused for `forgetAfter` go.
    func forgetSpots(existing: Set<UInt32>) {
        guard !existing.isEmpty else { return }   // the window list couldn't be read: release nothing
        spots.release(existing: existing)
        spots.forgetOld(now: nowSeconds)
        spotsDirty = true                         // also saves the refreshed last-used times
    }

    /// A move that didn't land: the spot record it made (at or after `since`) is undone,
    /// so where it ended up never becomes a spot. A spot it held goes back where it was;
    /// one the record added goes.
    func undoSpotRecord(_ w: CGWindow, key: String, since: Double) {
        let id = String(w.id)
        guard let last = lastRecorded[id], last.at >= since, let bundle = system.bundleID(pid: w.pid) else { return }
        lastRecorded[id] = nil
        if let before = last.spot {
            if let i = spots.spots[key]?[bundle]?.firstIndex(where: { $0.id == before.id }) { spots.spots[key]?[bundle]?[i] = before }
        } else if let added = spots.holders[key]?[id] {
            spots.spots[key]?[bundle]?.removeAll { $0.id == added }
            spots.holders[key]?[id] = nil
        }
        spotsDirty = true
    }

    /// Once per tick: save app spots if they changed, drop stale undo records (never one
    /// whose move is still waiting to be checked: a long job delays the check).
    func spotsTick() {
        let unchecked = Set(landing.pending().map { String($0) })
        lastRecorded = lastRecorded.filter { unchecked.contains($0.key) || nowSeconds - $0.value.at < Self.lastRecordedFor }
        heldByRestore = heldByRestore.filter { unchecked.contains($0.key) || nowSeconds - $0.value < Self.lastRecordedFor }
        guard spotsDirty else { return }
        spotsDirty = false
        spotStore.save(spots.spots)
    }
}

/// New windows go to a free spot for their app as soon as they settle (seen twice,
/// sitting still), at launch, after a restart or any time after; never later.
extension Shepherd {
    /// Ticks a new window waits for its kind before it's left where it is: one more than
    /// the kind rules need to settle a window that's unreadable or missing from the list.
    static let newKindWaitLimit = Shepherd.kindMissLimit + 1
    /// Seconds a ready new window waits for a running job before it's left where it is.
    static let newJobWait: Double = 10
    /// Times a new window the app moves by itself starts settling again before it's left.
    static let newResetLimit = 3

    /// Each settled tick, before the snapshot (and while a job runs, so new windows are
    /// still sighted). A window's first sighting is noted. At its next one, if it sat still
    /// and it's a main window, it goes to a free spot for its app (a click into it doesn't
    /// stop that; a drag does). One the app moved by itself waits to settle again (at most
    /// `newResetLimit` times). Anything else leaves it where it is, for good.
    func placeNewWindows(visible: [CGWindow], screens: [ScreenInfo], key: String) {
        let previous = previousSighting
        previousSighting = visible
        let t = Date().timeIntervalSince1970
        let mouse = system.lastMouseUse()?.timeIntervalSince1970
        let layout = book.layouts[key] ?? [:]
        func placed(_ id: String) -> Bool {
            spots.holds(key: key, window: id) || book.restoredIds.contains(id) || book.homeless.contains(id)
        }
        func handled(_ id: String) -> Bool { layout[id] != nil || placed(id) }
        var ready: [CGWindow] = []
        var shown = Set<String>()
        let shownIDs = Set(visible.map(\.id))
        for w in visible {
            let id = String(w.id)
            shown.insert(id)
            guard let first = firstSeen[id] else {
                guard !notNew.contains(id) else { continue }
                // A tab switch (Finder, Terminal): another tab of a window that's been open a while.
                if !handled(id), !LayoutBook.isTabSwitch(w, shownIDs: shownIDs, previous: previous),
                   let at = Geometry.whereIs(w.frame, in: screens) {
                    firstSeen[id] = (at, t)
                } else {
                    notNew.insert(id)
                }
                continue
            }
            // Placed meanwhile. A per-window entry made since is the snapshot's own record of
            // where it sits (while its kind is awaited), not a reason to leave it.
            if placed(id) { leaveFirstSeen(id); continue }
            let here = Geometry.whereIs(w.frame, in: screens)
            guard Geometry.sameSpot(here, first.at) else {
                // Moved with the mouse: you placed it (yours, and a spot).
                if let mouse, mouse > first.tick {
                    draggedNew.insert(id)
                    leaveFirstSeen(id)
                    continue
                }
                // Without: the app is settling it; this is its first sighting again, a few times.
                let resets = (newResets[id] ?? 0) + 1
                if let here, resets <= Self.newResetLimit {
                    firstSeen[id] = (here, t)
                    newResets[id] = resets
                } else {
                    leaveFirstSeen(id)
                }
                continue
            }
            switch isMainWindow(id) {
            case false?:
                leaveFirstSeen(id)   // a dialog or settings window
                continue
            case nil:
                let waits = (newKindWaits[id] ?? 0) + 1
                if waits > Self.newKindWaitLimit { leaveFirstSeen(id) } else { newKindWaits[id] = waits }
                continue
            case true?:
                break
            }
            if runner.current != nil {
                let since = newReadyAt[id] ?? t
                newReadyAt[id] = since
                if t - since > Self.newJobWait { leaveFirstSeen(id) }
                continue
            }
            ready.append(w)
        }
        for id in firstSeen.keys where !shown.contains(id) { leaveFirstSeen(id) }   // closed, minimized, another Space
        guard !ready.isEmpty else { return }
        for w in ready { leaveFirstSeen(String(w.id)) }   // decided now: placed, or left where it is
        placeNew(ready, screens: screens, key: key)
    }

    /// Never placed as a new window from now on.
    func leaveFirstSeen(_ id: String) {
        firstSeen[id] = nil
        newKindWaits[id] = nil
        newReadyAt[id] = nil
        newResets[id] = nil
        notNew.insert(id)
    }

    /// Ready new windows, grouped by app, into its free spots: one `.place` job.
    /// Windows with no free spot (or no bundle ID) are left where the app put them.
    func placeNew(_ windows: [CGWindow], screens: [ScreenInfo], key: String) {
        // Closed windows free their spots first: a ⌘W then ⌘N, or a quit and reopen, comes
        // sooner than the next `forgetSpots`.
        let existing = system.allWindowIDs()
        if !existing.isEmpty { spots.release(existing: existing) }
        var byBundle: [String: [CGWindow]] = [:]
        for w in windows where !spots.holds(key: key, window: String(w.id)) {
            guard let bundle = system.bundleID(pid: w.pid) else { continue }
            byBundle[bundle, default: []].append(w)
        }
        var plan: [pid_t: [UInt32: RestoreTarget]] = [:]
        var apps: [UInt32: String] = [:]
        for (bundle, ws) in byBundle.sorted(by: { $0.key < $1.key }) {
            let got = spots.assign(key: key, bundle: bundle, windows: ws.map { (String($0.id), Geometry.whereIs($0.frame, in: screens)) },
                                   now: nowSeconds)
            for w in ws {
                guard let spot = got[String(w.id)] else { continue }
                plan[w.pid, default: [:]][w.id] = RestoreTarget(id: String(w.id), screenUUID: spot.scr, unit: spot.unit,
                                                                from: Geometry.whereIs(w.frame, in: screens))
                apps[w.id] = w.app
            }
        }
        guard !plan.isEmpty else { return }
        spotsDirty = true
        placing = (key, Set(plan.values.flatMap { $0.keys }.map { String($0) }))
        let main = system.mainScreen()
        let tally = Tally<RestoreTarget>()
        let plannedAt = Date()
        let landing = self.landing, clock = landingClock
        let names = Dictionary(screens.map { ($0.uuid, $0.name) }, uniquingKeysWith: { a, _ in a })
        let steps: [JobStep] = plan.keys.sorted().map { pid in
            appStep(pid: pid, wanted: plan[pid]!, system: system, worker: jobWorker, timing: timing, tally: tally,
                    gate: { [weak self] in self?.book.lastSetup == key },
                    skip: { [weak self] id in
                        guard let self else { return true }
                        let wasYours = self.book.restoredIds.contains(String(id))
                        guard self.placedByYou(id, from: plan[pid]?[id]?.from, plannedAt: plannedAt, screens: screens) else { return false }
                        self.releasePlacing(String(id))      // never in the spot it was given
                        if !wasYours { self.draggedNew.insert(String(id)) }   // dragged: its place becomes a spot
                        return true
                    },
                    // Didn't land: Retry is the same move into its spot (a restore wouldn't place a new window).
                    action: Self.targetAction(screens: screens, main: main, pid: pid, landing: landing, clock: clock) { placer, t in
                        .move(placer, "\(names[t.screenUUID] ?? t.screenUUID) (\(Self.unitLabel(t.unit)))")
                    },
                    onMoved: { [weak self] id, t in
                        guard let self else { return }
                        self.book.restoredIds.insert(t.id)
                        self.placing?.pending.remove(t.id)   // in its spot: the hold is real now
                        let name = screens.first { $0.uuid == t.screenUUID }?.name ?? t.screenUUID
                        let why = self.inGuessingPeriod(pid: pid) ? "opened at launch" : "new window"
                        Log.info("\(apps[id] ?? "?") window \(id) → its spot on \(name) (\(Self.unitLabel(t.unit))), \(why)")
                    })
        }
        let count = plan.values.reduce(0) { $0 + $1.count }
        runner.run(.place, steps: steps, deadline: deadlineFor(windowCount: count)) { [weak self] _ in
            guard let self else { return }
            tally.settle()
            self.releasePlacing()   // not placed (refused, no answer, a newer move came first): free again
            guard self.book.lastSetup == key else { return }
            self.recordNow(tally.ids)   // the per-window layout; their held spot is refreshed, not added again
        }
    }

    /// Holds the running placement gave to windows it hasn't moved yet (`id`, or all of
    /// them) are dropped, so those spots are free again. Also when the job is stopped
    /// by a screen change or cleared as stale, which skips its `done`.
    func releasePlacing(_ id: String? = nil) {
        guard let p = placing else { return }
        for one in id.map({ [$0] }) ?? Array(p.pending) where p.pending.contains(one) {
            spots.holders[p.key]?[one] = nil
            placing?.pending.remove(one)
        }
        if id == nil { placing = nil }
    }

    /// At launch: windows an app opened shortly before Window Shepherd started (at login,
    /// after a restart) with no per-window entry are new, and this look is their first
    /// sighting. Every other window already open isn't.
    func noteNewAtStart(key: String) {
        let visible = system.visibleWindows()
        let screens = system.screens()
        let layout = book.layouts[key] ?? [:]
        let t = Date().timeIntervalSince1970
        for w in visible where layout[String(w.id)] == nil {
            guard let launched = system.launchDate(pid: w.pid), now().timeIntervalSince(launched) < restoreTiming.guessing,
                  let at = Geometry.whereIs(w.frame, in: screens) else { continue }
            firstSeen[String(w.id)] = (at, t)
        }
        let open = Set(system.allWindowIDs().map { String($0) }).union(visible.map { String($0.id) })
        notNew = open.subtracting(firstSeen.keys)
        previousSighting = visible
        requestKinds(visible.filter { firstSeen[String($0.id)] != nil })
    }

    /// New windows you dragged before they could be placed: once the snapshot has
    /// recorded them where they now sit, that place is a spot (yours).
    func recordDraggedNew(_ windows: [CGWindow], key: String, screens: [ScreenInfo]) {
        guard !draggedNew.isEmpty else { return }
        for w in windows where draggedNew.contains(String(w.id)) {
            let id = String(w.id)
            guard isMainWindow(id) != nil,
                  Geometry.sameSpot(book.layouts[key]?[id]?.spot, Geometry.whereIs(w.frame, in: screens)) else { continue }
            draggedNew.remove(id)
            recordSpot(w, key: key, screens: screens)
        }
    }

    /// At launch: holders aren't saved, so each open window takes back the spot its
    /// per-window entry puts it in (in every setup), or ⌘N would stack onto it.
    func holdOpenWindows() {
        let open = system.allWindowIDs()
        guard !open.isEmpty else { return }
        var bundles: [pid_t: String?] = [:]
        for (key, layout) in book.layouts {
            for (id, e) in layout.sorted(by: { $0.key < $1.key }) where UInt32(id).map(open.contains) == true {
                let pid = pid_t(e.pid)
                if bundles[pid] == nil { bundles.updateValue(system.bundleID(pid: pid), forKey: pid) }
                guard let bundle = bundles[pid] ?? nil else { continue }
                spots.hold(key: key, bundle: bundle, window: id, at: e.spot)
            }
        }
    }

    /// Forget closed windows.
    func forgetNewWindows(existing: Set<UInt32>) {
        guard !existing.isEmpty else { return }   // the window list couldn't be read
        let ids = Set(existing.map { String($0) })
        notNew.formIntersection(ids)
        draggedNew.formIntersection(ids)
    }

    /// "90% centered", "Full screen", "60% centered" (the undocked sizes), else "x%,y% w×h%".
    static func unitLabel(_ u: UnitRect) -> String {
        let named = UndockedWindows.Size.allCases.first { size in
            size.unit.map { Geometry.sameSpot(Spot(scr: "", unit: $0), Spot(scr: "", unit: u)) } ?? false
        }
        if let named { return named.rawValue }
        func pct(_ v: Double) -> Int { Int((v * 100).rounded()) }
        return "\(pct(u.x))%,\(pct(u.y))% \(pct(u.w))×\(pct(u.h))%"
    }
}
