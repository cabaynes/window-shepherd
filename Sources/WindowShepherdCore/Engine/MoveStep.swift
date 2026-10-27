import Foundation

/// What a job got done. `missed` = windows skipped (for the retry offer),
/// `waiting` = windows whose app is due another try later in the job.
@MainActor
public final class Tally<V> {
    public var moved = 0
    public var skipped: [String] = []
    public var ids = Set<String>()
    public var missed: [pid_t: [UInt32: V]] = [:]
    /// Windows whose move the app refused (an AX error) every time it was asked; also in `missed`.
    public var refused: [pid_t: [UInt32: V]] = [:]
    var waiting: [pid_t: (name: String, wanted: [UInt32: V])] = [:]

    public init() {}

    /// At the end of a job: apps still waiting for a retry (the job ran out
    /// of time or was interrupted) count as skipped.
    public func settle() {
        for (pid, w) in waiting.sorted(by: { $0.key < $1.key }) {
            skipped.append(w.name)
            missed[pid] = w.wanted
        }
        waiting = [:]
    }
}

public struct MoveTiming {
    /// One window taking longer than this to move: stop on that app for this try.
    /// (Safari normally takes 0.3–0.4 s per window while it re-lays out pages,
    /// and a move is now up to ~10 calls with the enhanced-UI switch: at 0.8 s,
    /// answering VS Code, Chrome and Transmission windows were skipped, 0.83–1.10 s.)
    public var windowLimit: TimeInterval = 1.5
    /// Listing windows: empty after this long means the 0.5 s timeout was hit.
    public var listSlow: TimeInterval = 0.4
    /// Seconds before the 2nd and 3rd try of an app that didn't answer.
    public var retryWaits: [TimeInterval] = [2, 4]
    /// With a patience deadline, later waits double from the last of `retryWaits`, up to this.
    public var maxWait: TimeInterval = 16

    public init(windowLimit: TimeInterval = 1.5, listSlow: TimeInterval = 0.4, retryWaits: [TimeInterval] = [2, 4]) {
        self.windowLimit = windowLimit; self.listSlow = listSlow; self.retryWaits = retryWaits
    }

    public static let standard = MoveTiming()

    /// The wait before try `n + 1`, or nil to give up. Without a deadline:
    /// `retryWaits`, then stop. With one: keep going, waits growing, while
    /// the next try still starts before it.
    func wait(afterTry n: Int, until: Date?) -> TimeInterval? {
        let w: TimeInterval
        if n <= retryWaits.count {
            w = retryWaits[n - 1]
        } else {
            guard until != nil else { return nil }
            w = min(maxWait, (retryWaits.last ?? 1) * pow(2, Double(n - retryWaits.count)))
        }
        if let until, Date().addingTimeInterval(w) >= until { return nil }
        return w
    }
}

/// A job step that pauses the job until `secs` from now (nothing is held).
@MainActor
func waitStep(_ secs: TimeInterval) -> JobStep {
    let until = Date().addingTimeInterval(secs)
    return { _ in until.timeIntervalSinceNow }
}

private final class Flag { var on = false }

/// One step that lists the app's windows (on the worker), then queues one
/// step per wanted window right after itself. Busy-but-working apps are
/// fine. An app is "not responding" only if listing its windows fails (or
/// comes back empty after `listSlow`), or one window takes over
/// `windowLimit`; then we stop on that app, wait (`retryWaits`) and try its
/// remaining windows again at the end of the job. Windows the app refuses to
/// move get the same retries. With `patientUntil`, retries go on (waits
/// growing to `maxWait`) until that time instead of stopping after `retryWaits`. The Hammerspoon log showed
/// 43 of 48 skipped apps answering seconds later: busy, not hung.
///
/// `action` runs on the worker; `gate` (main) can veto the rest of the job and
/// `skip` (main) one window, just before it moves; `onMoved` (main) records a success.
@MainActor
public func appStep<V>(pid: pid_t, wanted: [UInt32: V], system: WindowSystem, worker: AXWorker, timing: MoveTiming,
                       tally: Tally<V>, try attempt: Int = 1, partly: Bool = false, patientUntil: Date? = nil,
                       gate: @escaping @MainActor () -> Bool = { true },
                       skip: @escaping @MainActor (UInt32) -> Bool = { _ in false },
                       action: @escaping (WindowHandle, V) throws -> Void,
                       onMoved: @escaping @MainActor (UInt32, V) -> Void = { _, _ in }) -> JobStep {
    return { ctx in
        tally.waiting[pid] = nil
        guard let name = system.appName(pid: pid) else { return nil }   // the app quit
        let movedBefore = tally.moved
        var done = Set<UInt32>()   // moved, so a give-up records only the rest

        @MainActor func giveUp(_ why: String) {
            let rest = wanted.filter { !done.contains($0.key) }
            guard !rest.isEmpty else { return }
            let wasPartly = partly || tally.moved > movedBefore
            if let wait = timing.wait(afterTry: attempt, until: patientUntil) {
                Log.info("\(name) not responding (\(why)), trying again in \(Int(wait.rounded()))s")
                tally.waiting[pid] = (name, rest)
                ctx.append(waitStep(wait))
                ctx.append(appStep(pid: pid, wanted: rest, system: system, worker: worker, timing: timing, tally: tally,
                                   try: attempt + 1, partly: wasPartly, patientUntil: patientUntil,
                                   gate: gate, skip: skip, action: action, onMoved: onMoved))
                return
            }
            tally.skipped.append(wasPartly ? name + ", partly" : name)
            Log.info("skipped \(name) (\(why), after \(attempt) tries)")
            tally.missed[pid] = rest
        }

        let t = Date()
        let listed: [(UInt32?, WindowHandle)]? = await worker.run {
            guard let wins = try? system.appWindows(pid: pid) else { return nil }
            return wins.map { ($0.windowID, $0) }
        }
        let took = Date().timeIntervalSince(t)
        guard let listed, !(listed.isEmpty && took > timing.listSlow) else {
            giveUp(String(format: "listing windows took %.2fs", took))
            return nil
        }
        let dead = Flag()
        var pos = ctx.index
        let found = Set(listed.compactMap(\.0)).intersection(wanted.keys)
        var yours = 0
        var refused: [Int32] = []   // AX error codes of moves that failed
        var refusedIDs = Set<UInt32>()
        for (maybeID, win) in listed {
            guard let id = maybeID, let value = wanted[id] else { continue }
            pos += 1
            ctx.insert({ _ in
                if dead.on || !gate() { return nil }
                if skip(id) { yours += 1; return nil }
                let t1 = Date()
                let error: Int32? = await worker.run {
                    do { try action(win, value); return nil } catch { return (error as? AXFailure)?.code ?? 0 }
                }
                let ok = error == nil
                if let error { refused.append(error); refusedIDs.insert(id) }
                guard gate() else { return nil }   // the screens changed meanwhile: it belongs to the old setup
                if ok {
                    done.insert(id)
                    tally.moved += 1
                    tally.ids.insert(String(id))
                    onMoved(id, value)
                }
                let took1 = Date().timeIntervalSince(t1)
                if took1 > timing.windowLimit {
                    dead.on = true
                    giveUp(String(format: "one window took %.2fs", took1))
                }
                return nil
            }, at: pos)
        }
        // After its windows: say why any it wanted didn't move (a give-up says so itself).
        ctx.insert({ _ in
            guard !dead.on, gate(), done.count < wanted.count else { return nil }
            var line = "\(name): \(wanted.count) to move, \(found.count) in its window list, \(done.count) moved"
            if yours > 0 { line += ", \(yours) left where you put them" }
            if !refused.isEmpty { line += ", \(refused.count) refused (AX \(refused.map(String.init).joined(separator: " ")))" }
            Log.info(line)
            let again = wanted.filter { refusedIDs.contains($0.key) }
            guard !again.isEmpty else { return nil }
            if let wait = timing.wait(afterTry: attempt, until: patientUntil) {
                tally.waiting[pid] = (name, again)
                ctx.append(waitStep(wait))
                ctx.append(appStep(pid: pid, wanted: again, system: system, worker: worker, timing: timing, tally: tally,
                                   try: attempt + 1, partly: partly || !done.isEmpty, patientUntil: patientUntil,
                                   gate: gate, skip: skip, action: action, onMoved: onMoved))
            } else {
                tally.refused[pid, default: [:]].merge(again) { a, _ in a }
                tally.missed[pid, default: [:]].merge(again) { a, _ in a }
            }
            return nil
        }, at: pos + 1)
        return nil
    }
}

/// The on-screen message for a finished job.
public func reportText(_ head: String, skipped: [String], hasMissed: Bool, problem: JobProblem?, refused: Int = 0) -> String {
    var msg = head
    if !skipped.isEmpty {
        msg += "\n(skipped, not responding: " + skipped.joined(separator: ", ") + ")"
    }
    if refused > 0 { msg += "\n(\(refused) window\(refused == 1 ? "" : "s") refused to move)" }
    if hasMissed && (!skipped.isEmpty || refused > 0) { msg += "\nRetry from the ⧉ menu" }
    if problem == .outOfTime { msg += "\n(stopped: took too long)" }
    if problem == .interrupted { msg += "\n(interrupted by a newer move)" }
    return msg
}
