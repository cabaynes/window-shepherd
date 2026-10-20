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
    /// Where the previous snapshot saw each window (same setup).
    var lastSeenAt: [String: Spot] = [:]

    public init(layouts: [String: [String: LayoutEntry]]) { self.layouts = layouts }

    /// Keep only entries whose app still runs under the same name (pids get
    /// reused after a restart).
    public func prune(running: [pid_t: String]) {
        for (key, layout) in layouts {
            layouts[key] = layout.filter { running[$0.value.pid] == $0.value.app }
        }
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
            }
            layout[id]?.seen = now
            if Geometry.sameSpot(spot, lastSeenAt[id]) && protect[id] == nil {
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
        }
        layouts[key] = layout
    }

    public func setupChanged(to key: String, now: Double) {
        lastSetup = key
        lastSeenAt = [:]
        restoredIds = []
        protect = [:]
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
        for (id, e) in layout {
            if !running.contains(e.pid) {
                layout[id] = nil                       // that app has quit; its windows are gone
            } else if let p = protect[id], let at = nowAt[id], !Geometry.sameSpot(at, p) {
                restoredIds.insert(id)                 // an earlier pass missed it and you've since moved it
                protect[id] = nil
            } else if connected.contains(e.scr) && !restoredIds.contains(id) && Geometry.sameSpot(nowAt[id], e.spot) {
                restoredIds.insert(id)                 // already in place
            } else if connected.contains(e.scr) && !restoredIds.contains(id), let wid = UInt32(id) {
                plan[e.pid, default: [:]][wid] = RestoreTarget(id: id, screenUUID: e.scr, unit: e.unit, from: nowAt[id])
            }
        }
        layouts[key] = layout
        return plan
    }

    /// After a pass: windows it couldn't move are still where macOS left
    /// them; don't let a snapshot record that spot as their home.
    public func restoreFinished(plan: [pid_t: [UInt32: RestoreTarget]]) {
        for targets in plan.values {
            for t in targets.values where !restoredIds.contains(t.id) {
                if let from = t.from { protect[t.id] = from }
            }
        }
    }
}
