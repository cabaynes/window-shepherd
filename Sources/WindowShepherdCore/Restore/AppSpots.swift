import Foundation

/// One remembered place for a window of an app, for one screen setup.
public struct AppSpot: Codable, Equatable {
    /// UUID string, stable for the spot's life.
    public var id: String
    public var scr: String
    public var unit: UnitRect
    /// Last time a window was put in it or sat in it.
    public var used: Double

    public init(id: String, scr: String, unit: UnitRect, used: Double) {
        self.id = id; self.scr = scr; self.unit = unit; self.used = used
    }

    var spot: Spot { Spot(scr: scr, unit: unit) }
}

/// setup key → bundle ID → spots.
public typealias AppSpotMap = [String: [String: [AppSpot]]]

/// Per screen setup and app, the places its windows have been, so a window
/// that opens later (after a restart or relaunch) can go to one. Pure state,
/// no timers and no app calls.
@MainActor
public final class AppSpotBook {
    public var spots: AppSpotMap
    /// Runtime only (not saved): setup key → window id → the spot id it holds.
    public var holders: [String: [String: String]] = [:]
    public static let maxPerApp = 20

    public init(spots: AppSpotMap) { self.spots = spots }

    private func isHeld(_ id: String, key: String) -> Bool {
        holders[key]?.values.contains(id) ?? false
    }

    /// A confirmed placement (yours or Window Shepherd's). If the window holds a
    /// spot for this setup and app, that spot moves here; otherwise a new spot is
    /// added and held. Over `maxPerApp`, the least recently used unheld spot goes
    /// (if every spot is held, the list stays over the cap until some are released).
    public func record(key: String, bundle: String, window: String, at spot: Spot, now: Double) {
        var list = spots[key]?[bundle] ?? []
        if let held = holders[key]?[window], let i = list.firstIndex(where: { $0.id == held }) {
            list[i].scr = spot.scr
            list[i].unit = spot.unit
            list[i].used = now
        } else {
            let new = AppSpot(id: UUID().uuidString, scr: spot.scr, unit: spot.unit, used: now)
            list.append(new)
            holders[key, default: [:]][window] = new.id
        }
        while list.count > Self.maxPerApp {
            let free = list.indices.filter { !isHeld(list[$0].id, key: key) }
            guard let drop = free.min(by: { list[$0].used < list[$1].used }) else { break }
            list.remove(at: drop)
        }
        spots[key, default: [:]][bundle] = list
    }

    /// Refresh `used` for every held spot whose holder is in `visible`.
    public func touch(key: String, visible: Set<String>, now: Double) {
        guard let held = holders[key] else { return }
        let ids = Set(held.filter { visible.contains($0.key) }.values)
        guard !ids.isEmpty, var byApp = spots[key] else { return }
        for (bundle, list) in byApp {
            byApp[bundle] = list.map { s in
                var s = s
                if ids.contains(s.id) { s.used = now }
                return s
            }
        }
        spots[key] = byApp
    }

    /// Drop holders whose window no longer exists (any setup); their spots stay, free.
    public func release(existing: Set<UInt32>) {
        for (key, held) in holders {
            holders[key] = held.filter { UInt32($0.key).map(existing.contains) ?? false }
        }
    }

    /// Drop unheld spots unused for `forgetAfter`.
    public func forgetOld(now: Double) {
        for (key, byApp) in spots {
            for (bundle, list) in byApp {
                spots[key]?[bundle] = list.filter { isHeld($0.id, key: key) || now - $0.used < forgetAfter }
            }
        }
    }

    /// Free spots for windows this book doesn't place yet: takes the N most
    /// recently used free spots, then pairs each window with the nearest of
    /// them to where it is (`at`), and marks them held. Returns window id → spot.
    public func assign(key: String, bundle: String, windows: [(id: String, at: Spot?)], now: Double) -> [String: AppSpot] {
        let free = (spots[key]?[bundle] ?? []).filter { !isHeld($0.id, key: key) }
        // Stable sort: ties keep their list order.
        let ranked = free.enumerated().sorted { ($0.element.used, -$0.offset) > ($1.element.used, -$1.offset) }
            .map(\.element)
        let pool = Array(ranked.prefix(windows.count))

        func distance(_ w: Spot?, _ s: AppSpot) -> Double {
            guard let w, w.scr == s.scr else { return 10 }
            let dx = (w.unit.x + w.unit.w / 2) - (s.unit.x + s.unit.w / 2)
            let dy = (w.unit.y + w.unit.h / 2) - (s.unit.y + s.unit.h / 2)
            return (dx * dx + dy * dy).squareRoot()
        }

        var pairs: [(d: Double, spot: Int, win: Int)] = []
        for (si, s) in pool.enumerated() {
            for (wi, w) in windows.enumerated() { pairs.append((distance(w.at, s), si, wi)) }
        }
        // Closest first; ties by recency (spot order), then window order.
        pairs.sort { ($0.d, $0.spot, $0.win) < ($1.d, $1.spot, $1.win) }

        var usedSpots = Set<Int>(), usedWins = Set<Int>()
        var result: [String: AppSpot] = [:]
        for p in pairs where !usedSpots.contains(p.spot) && !usedWins.contains(p.win) {
            usedSpots.insert(p.spot); usedWins.insert(p.win)
            var s = pool[p.spot]
            s.used = now
            result[windows[p.win].id] = s
            holders[key, default: [:]][windows[p.win].id] = s.id
            if let i = spots[key]?[bundle]?.firstIndex(where: { $0.id == s.id }) { spots[key]?[bundle]?[i].used = now }
        }
        return result
    }

    /// True if the window holds a spot in this setup.
    public func holds(key: String, window: String) -> Bool {
        holders[key]?[window] != nil
    }
}
