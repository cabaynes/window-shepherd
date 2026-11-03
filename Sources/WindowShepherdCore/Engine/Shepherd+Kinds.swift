import Foundation

/// Which windows are main windows (not dialogs, settings windows or panels).
/// Learned off the main thread, one worker call per app; a window whose app
/// answers slowly simply stays unknown until it does.
extension Shepherd {
    static let kindMissLimit = 3

    /// Is this a main window? nil = not learned yet.
    public func isMainWindow(_ id: String) -> Bool? { kinds[id] }

    /// Ask for the kind of every visible window we don't know yet.
    func requestKinds(_ windows: [CGWindow]) {
        var wanted: [pid_t: [UInt32]] = [:]
        for w in windows where kinds[String(w.id)] == nil && !kindsInFlight.contains(w.pid) {
            wanted[w.pid, default: []].append(w.id)
        }
        for (pid, ids) in wanted {
            kindsInFlight.insert(pid)
            let system = self.system
            let worker = kindWorker
            Task { @MainActor [weak self] in
                let answers: (kinds: [UInt32: Bool?], complete: Bool)? = await worker.run {
                    // A failed or timed-out list says nothing about the windows: record nothing.
                    guard let list = try? system.appWindows(pid: pid) else { return nil }
                    var out: [UInt32: Bool?] = [:]
                    var complete = true   // every listed window's id was read
                    for h in list {
                        guard let id = h.windowID else { complete = false; continue }
                        if ids.contains(id) { out[id] = h.isStandard }
                    }
                    return (out, complete)
                }
                guard let self else { return }
                self.kindsInFlight.remove(pid)
                guard let answers else { return }
                for id in ids {
                    let key = String(id)
                    if let known = answers.kinds[id], let isStandard = known {
                        self.kinds[key] = isStandard
                    } else if answers.kinds[id] == nil && answers.complete {
                        self.kinds[key] = false   // not in the app's own list: a sheet
                    } else {
                        // Unreadable: ask again on a later tick, then count it as a main window.
                        let misses = (self.kindMisses[key] ?? 0) + 1
                        self.kindMisses[key] = misses
                        if misses >= Self.kindMissLimit { self.kinds[key] = true }
                    }
                }
            }
        }
    }

    /// Drop what we learned about windows that no longer exist.
    func forgetKinds() {
        let existing = Set(system.allWindowIDs().map { String($0) })
        kinds = kinds.filter { existing.contains($0.key) }
        kindMisses = kindMisses.filter { existing.contains($0.key) }
    }
}
