import Foundation

/// Where a window was last seen for one screen setup.
public struct LayoutEntry: Codable, Equatable {
    public var pid: Int32
    public var app: String
    public var scr: String
    public var unit: UnitRect
    public var seen: Double

    public init(pid: Int32, app: String, scr: String, unit: UnitRect, seen: Double) {
        self.pid = pid; self.app = app; self.scr = scr; self.unit = unit; self.seen = seen
    }

    var spot: Spot { Spot(scr: scr, unit: unit) }
}

/// A window a restore pass should put back.
public struct RestoreTarget: Equatable {
    public let id: String
    public let screenUUID: String
    public let unit: UnitRect
    /// Where it is now (macOS's spot), protected if the move fails.
    public let from: Spot?
    /// Centre it at its own size on the screen instead of using `unit`.
    public var keepSize = false
}

/// What the last restore plan made of each remembered window, for the log.
public struct PlanCounts: Equatable {
    public var remembered = 0, toMove = 0, inPlace = 0, doneEarlier = 0, yours = 0, screenGone = 0, appQuit = 0

    public var summary: String {
        "\(remembered) remembered: \(toMove) to move, \(inPlace) already in place, \(doneEarlier) done earlier, "
            + "\(yours) moved by you, \(screenGone) on a screen not connected, \(appQuit) from apps that quit"
    }
}

/// A screen combination's layout as it was when you last left it in good
/// order: Revert's target, and what a bad visit's live layout is rolled back to.
public struct FrozenCopy: Codable, Equatable {
    public var layout: [String: LayoutEntry]
    public var at: Double
    public init(layout: [String: LayoutEntry], at: Double) { self.layout = layout; self.at = at }
}

/// Forget remembered windows not seen for this long.
public let forgetAfter: Double = 30 * 86400

/// Auto-restore's memory, per screen setup: for each combination of
/// connected screens, where every window sits. Pure state, no timers and no
/// app calls (the Shepherd drives it), ported from the Hammerspoon version.
@MainActor
public final class LayoutBook {
    /// setup key → window id → where it sits.
    public var layouts: [String: [String: LayoutEntry]]
    public var lastSetup: String?
    /// false from a screen change until the first restore pass is done.
    public var settled = true
    public var changedAt = 0.0
    /// Windows put back, or placed by you, since the last setup change.
    public var restoredIds = Set<String>()
    /// Window → spot a restore failed to move it from (don't record that spot).
    public var protect: [String: Spot] = [:]
    /// Windows a restore wanted to move but couldn't see (on another Space,
    /// minimized): put back when they show up, never recorded where they appear.
    public var offscreen = Set<String>()
    /// Where the previous snapshot saw each window (same setup).
    var lastSeenAt: [String: Spot] = [:]
    /// How the last `restorePlan` sorted the remembered windows.
    public private(set) var planCounts = PlanCounts()
    /// setup key → its frozen copy, taken when you leave a combination.
    public var frozen: [String: FrozenCopy] = [:]
    /// Visible windows a restore wanted to move but couldn't, until they reach
    /// their spot, close, or you move them yourself.
    public var leftBehind = Set<String>()
    /// Windows open at the last screen change that added a screen, with no
    /// spot remembered for the new combination: the undocked setting places them.
    public var homeless = Set<String>()
    /// A combination must be in use this long before leaving it replaces its frozen copy.
    public var minActiveToFreeze: Double = 60

    public init(layouts: [String: [String: LayoutEntry]]) { self.layouts = layouts }

    /// Keep only entries whose app still runs under the same name (pids get
    /// reused after a restart).
    public func prune(running: [pid_t: String]) {
        for (key, layout) in layouts {
            layouts[key] = layout.filter { running[$0.value.pid] == $0.value.app }
        }
    }

    /// Drop remembered windows that have closed while their app kept running
    /// (`existing` = every window that exists, any Space). Quit apps' entries
    /// are left for `restorePlan`/`prune`. Returns true if anything was dropped.
    @discardableResult
    public func forgetClosed(existing: Set<UInt32>, running: Set<pid_t>) -> Bool {
        var dropped = false
        for (key, layout) in layouts {
            let kept = layout.filter { id, e in !running.contains(e.pid) || UInt32(id).map(existing.contains) ?? false }
            if kept.count != layout.count { layouts[key] = kept; dropped = true }
        }
        for (key, copy) in frozen {
            let kept = copy.layout.filter { id, e in !running.contains(e.pid) || UInt32(id).map(existing.contains) ?? false }
            if kept.count != copy.layout.count { frozen[key]?.layout = kept; dropped = true }
        }
        return dropped
    }

    /// Record where windows are. A spot counts only when seen twice in a row
    /// (2 s apart), so a check that lands mid-unplug, after macOS shoved
    /// windows aside, can't overwrite the layout. Returns true if it changed.
    @discardableResult
    public func snapshot(key: String, windows: [CGWindow], screens: [ScreenInfo], now: Double) -> Bool {
        var layout = layouts[key] ?? [:]
        var changed = false
        var seenNow: [String: Spot] = [:]
        for w in windows {
            guard let spot = Geometry.whereIs(w.frame, in: screens) else { continue }
            let id = String(w.id)
            seenNow[id] = spot
            if let p = protect[id], !Geometry.sameSpot(spot, p) {   // you moved it: yours now, restore leaves it
                protect[id] = nil
                restoredIds.insert(id)
                markYours(id)
            }
            layout[id]?.seen = now
            if Geometry.sameSpot(spot, lastSeenAt[id]) && protect[id] == nil && !offscreen.contains(id) {
                if !Geometry.sameSpot(spot, layout[id]?.spot) { changed = true }
                layout[id] = LayoutEntry(pid: w.pid, app: w.app, scr: spot.scr, unit: spot.unit, seen: now)
            }
        }
        lastSeenAt = seenNow
        for (id, e) in layout where now - e.seen > forgetAfter {
            layout[id] = nil
            changed = true
        }
        layouts[key] = layout
        return changed
    }

    /// Record where the windows a hotkey/menu move just placed are now,
    /// without waiting for two sightings, so an unplug right after can't undo
    /// it. Only those windows: others may still be where macOS shoved them.
    public func recordNow(ids: Set<String>, key: String, windows: [CGWindow], screens: [ScreenInfo], now: Double) {
        guard key == lastSetup, !ids.isEmpty else { return }
        var layout = layouts[key] ?? [:]
        for w in windows where ids.contains(String(w.id)) {
            guard let spot = Geometry.whereIs(w.frame, in: screens) else { continue }
            let id = String(w.id)
            layout[id] = LayoutEntry(pid: w.pid, app: w.app, scr: spot.scr, unit: spot.unit, seen: now)
            protect[id] = nil
            markYours(id)
        }
        layouts[key] = layout
    }

    /// You placed this window yourself: it isn't stranded any more.
    public func markYours(_ id: String) { leftBehind.remove(id) }

    /// Drop left-behind windows that reached their live spot or closed
    /// (`existing` = all windows on any Space). Cheap: no app calls.
    public func resolve(windows: [CGWindow], screens: [ScreenInfo], existing: Set<UInt32>) {
        guard !leftBehind.isEmpty, let key = lastSetup else { return }
        let home = layouts[key] ?? [:]
        for w in windows {
            let id = String(w.id)
            if leftBehind.contains(id), let e = home[id], Geometry.sameSpot(Geometry.whereIs(w.frame, in: screens), e.spot) {
                leftBehind.remove(id)
            }
        }
        leftBehind = leftBehind.filter { UInt32($0).map(existing.contains) ?? false }
    }

    /// How many left-behind windows are on screen now.
    public func unresolvedVisible(_ windows: [CGWindow]) -> Int {
        windows.filter { leftBehind.contains(String($0.id)) }.count
    }

    /// Leaving a combination in good order (in use a minute, nothing left
    /// behind) freezes its layout; otherwise its live layout goes back to the
    /// last frozen copy, so a stranded spot never becomes a window's home.
    public func setupChanged(to key: String, now: Double) {
        if let old = lastSetup, old != key {
            if now - changedAt >= minActiveToFreeze && leftBehind.isEmpty {
                frozen[old] = FrozenCopy(layout: layouts[old] ?? [:], at: now)
            } else if let f = frozen[old] {
                layouts[old] = f.layout
            }
        }
        leftBehind = []
        homeless = []
        lastSetup = key
        lastSeenAt = [:]
        restoredIds = []
        protect = [:]
        offscreen = []
        settled = false
        changedAt = now
    }

    /// The windows a restore pass should move, by app; nil when nothing is
    /// remembered for this setup. Updates the bookkeeping as it goes: quit
    /// apps' windows are dropped, windows already in place (or moved by you
    /// since) are marked so later passes leave them alone.
    public func restorePlan(key: String, windows: [CGWindow], screens: [ScreenInfo],
                            running: Set<pid_t>) -> [pid_t: [UInt32: RestoreTarget]]? {
        guard var layout = layouts[key] else { return nil }
        let connected = Set(screens.map(\.uuid))
        var nowAt: [String: Spot] = [:]
        for w in windows { nowAt[String(w.id)] = Geometry.whereIs(w.frame, in: screens) }
        var plan: [pid_t: [UInt32: RestoreTarget]] = [:]
        var n = PlanCounts(remembered: layout.count)
        for (id, e) in layout {
            if !running.contains(e.pid) {
                layout[id] = nil                       // that app has quit; its windows are gone
                n.appQuit += 1
            } else if let p = protect[id], let at = nowAt[id], !Geometry.sameSpot(at, p) {
                restoredIds.insert(id)                 // an earlier pass missed it and you've since moved it
                protect[id] = nil
                markYours(id)
                n.yours += 1
            } else if !connected.contains(e.scr) {
                n.screenGone += 1
            } else if restoredIds.contains(id) {
                n.doneEarlier += 1
            } else if Geometry.sameSpot(nowAt[id], e.spot) {
                restoredIds.insert(id)                 // already in place
                n.inPlace += 1
            } else if let wid = UInt32(id) {
                plan[e.pid, default: [:]][wid] = RestoreTarget(id: id, screenUUID: e.scr, unit: e.unit, from: nowAt[id])
                n.toMove += 1
            }
        }
        planCounts = n
        layouts[key] = layout
        return plan
    }

    /// True when a window the restore couldn't see is on screen now.
    public func offscreenVisible(_ windows: [CGWindow]) -> Bool {
        !offscreen.isEmpty && windows.contains { offscreen.contains(String($0.id)) && !restoredIds.contains(String($0.id)) }
    }

    /// After a pass: windows it couldn't move are still where macOS left
    /// them; don't let a snapshot record that spot as their home.
    /// `visible` = windows on screen now: those it couldn't move are left behind.
    public func restoreFinished(plan: [pid_t: [UInt32: RestoreTarget]], visible: Set<String> = []) {
        for targets in plan.values {
            for t in targets.values {
                if restoredIds.contains(t.id) {
                    offscreen.remove(t.id)
                    leftBehind.remove(t.id)
                } else if let from = t.from {
                    protect[t.id] = from
                    if visible.contains(t.id) { leftBehind.insert(t.id) }
                } else {
                    offscreen.insert(t.id)   // not on screen now: catch it when it appears
                }
            }
        }
    }
}
