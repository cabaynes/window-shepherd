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

    /// Once per tick: save app spots if they changed, drop stale undo records.
    func spotsTick() {
        lastRecorded = lastRecorded.filter { nowSeconds - $0.value.at < Self.lastRecordedFor }
        guard spotsDirty else { return }
        spotsDirty = false
        spotStore.save(spots.spots)
    }
}
