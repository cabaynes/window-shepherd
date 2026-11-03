import Foundation

/// What each move asked for, filled from worker threads (locked), checked on main.
final class Landing: @unchecked Sendable {
    struct Expect {
        let pid: pid_t
        let id: UInt32
        let wanted: CGRect
        let resizable: Bool
        let at: Double
        let retry: Retry
    }

    /// How the Retry row tries a window again: the same move (its placer and label),
    /// or a restore pass.
    enum Retry: Equatable { case move(Placer, String), restore }

    private let lock = NSLock()
    private var waiting: [Expect] = []

    /// A newer move of the same window replaces what the older one asked for.
    func expect(_ e: Expect) {
        lock.lock(); defer { lock.unlock() }
        waiting.removeAll { $0.id == e.id }
        waiting.append(e)
    }

    /// Expectations older than `after` seconds, removed and returned.
    func due(now: Double, after: Double) -> [Expect] {
        lock.lock(); defer { lock.unlock() }
        let ready = waiting.filter { now - $0.at >= after }
        waiting.removeAll { now - $0.at >= after }
        return ready
    }

    /// Windows with a move not checked yet: where they are isn't trusted until it is.
    func pending() -> Set<UInt32> {
        lock.lock(); defer { lock.unlock() }
        return Set(waiting.map(\.id))
    }
}

/// A move counts as done only once the window is seen where it was sent, from
/// the CoreGraphics list a couple of seconds later (so windows still animating
/// aren't misjudged). A miss is left behind and offered in the Retry row; it is
/// never sent again from here (re-sending a position left Chrome stuck part-way).
extension Shepherd {
    /// How long after a move its window is checked (at the next settled tick).
    static let landingCheckAfter: Double = 1.5
    /// Points a window may be off and still count as landed (apps round, shadows).
    static let landingSlack: CGFloat = 4

    /// The clock for `Landing.Expect.at`, safe to call from a worker.
    var landingClock: () -> Double {
        let now = self.now
        return { now().timeIntervalSince1970 }
    }

    /// Each settled tick, before the snapshot (so a miss is protected before it can be recorded).
    func checkLandings(visible: [CGWindow], screens: [ScreenInfo], key: String) {
        let due = landing.due(now: nowSeconds, after: Self.landingCheckAfter)
        guard !due.isEmpty else { return }
        let byID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var misses: [(Landing.Expect, CGWindow)] = []
        for e in due {
            // Asked before the last screen change: its target was for the old setup.
            guard e.at >= book.changedAt, let w = byID[e.id] else { continue }   // closed, minimized, another Space
            if !Self.landed(w.frame, wanted: e.wanted, resizable: e.resizable) { misses.append((e, w)) }
        }
        guard !misses.isEmpty else { return }
        var groups: [(retry: Landing.Retry, byPid: [pid_t: Set<UInt32>])] = []
        func add(_ r: Landing.Retry, _ pid: pid_t, _ id: UInt32) {
            if let i = groups.firstIndex(where: { $0.retry == r }) {
                groups[i].byPid[pid, default: []].insert(id)
            } else {
                groups.append((r, [pid: [id]]))
            }
        }
        var restoreAgain = Set<String>()
        for (e, w) in misses {
            missed(e, w, screens: screens, key: key)
            add(e.retry, e.pid, e.id)
            if e.retry == .restore { restoreAgain.insert(String(e.id)) }
        }
        store.save(book.layouts)
        // Windows the job itself skipped stay in the offer, merged by how they're retried.
        if let old = retryOffer, let r = old.retry {
            for (pid, ids) in old.missed { for id in ids { add(r, pid, id) } }
        }
        var all: [pid_t: Set<UInt32>] = [:]
        for g in groups { all.merge(g.byPid) { $0.union($1) } }
        let kind: JobKind = groups.contains { $0.retry != .restore } ? .move : .restore
        retryOffer = RetryOffer(kind: kind, at: now(), missed: all, run: { [weak self] picked in
            guard let self else { return }
            var restoreToo = false
            for g in groups {
                var sub: [pid_t: Set<UInt32>] = [:]
                for (pid, ids) in g.byPid {
                    let both = ids.intersection(picked[pid] ?? [])
                    if !both.isEmpty { sub[pid] = both }
                }
                guard !sub.isEmpty else { continue }
                switch g.retry {
                case .restore: restoreToo = true
                case let .move(placer, label): self.apply(Selection(byPid: sub, retry: true), placer: placer, label: label)
                }
            }
            guard restoreToo else { return }
            // Kept in restoredIds so no later pass sends them again by itself; the Retry row
            // lets them go once more, unless you've moved them since (no longer protected).
            for id in restoreAgain where self.book.protect[id] != nil { self.book.restoredIds.remove(id) }
            self.restore()   // after a move above, it waits for it
        })
        setFlashing(true)
    }

    /// Where it ended up counts: the position within a few points, and the size,
    /// if the app lets it change, no smaller than asked (an imposed size is fine).
    static func landed(_ f: CGRect, wanted: CGRect, resizable: Bool) -> Bool {
        let s = landingSlack
        guard abs(f.minX - wanted.minX) <= s, abs(f.minY - wanted.minY) <= s else { return false }
        return !resizable || (f.width >= wanted.width - s && f.height >= wanted.height - s)
    }

    /// One window that didn't land: logged, left behind, and where it ended up is
    /// never its per-window entry or an app spot.
    private func missed(_ e: Landing.Expect, _ w: CGWindow, screens: [ScreenInfo], key: String) {
        func box(_ r: CGRect) -> String {
            func n(_ v: CGFloat) -> Int { Int(v.rounded()) }
            return "\(n(r.minX)),\(n(r.minY)) \(n(r.width))×\(n(r.height))"
        }
        Log.info("\(w.app) window \(e.id) didn't land: asked \(box(e.wanted)), ended at \(box(w.frame))")
        let id = String(e.id)
        book.leftBehind.insert(id)
        if let at = Geometry.whereIs(w.frame, in: screens) { book.protect[id] = at }
        undoSpotRecord(w, key: key, since: e.at)
        if e.retry == .restore, let t = heldByRestore[id], t >= e.at {
            // Put in a free app spot by a restore: the spot stays free, and a Retry picks one again.
            heldByRestore[id] = nil
            spots.holders[key]?[id] = nil
            spotsDirty = true
            return
        }
        guard let sent = Geometry.whereIs(e.wanted, in: screens) else { return }
        book.layouts[key, default: [:]][id] = LayoutEntry(pid: w.pid, app: w.app, scr: sent.scr, unit: sent.unit, seen: nowSeconds)
    }
}
