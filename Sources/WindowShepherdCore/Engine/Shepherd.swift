import Foundation

/// Which windows an action applies to: one window (`winId`), one app
/// (`pid`), exact windows (`byPid`, for retries), or everything.
public struct Selection: Equatable {
    public var pid: pid_t?
    public var winId: UInt32?
    public var byPid: [pid_t: Set<UInt32>]?
    public var quiet = false
    public var retry = false

    public init(pid: pid_t? = nil, winId: UInt32? = nil, byPid: [pid_t: Set<UInt32>]? = nil, quiet: Bool = false, retry: Bool = false) {
        self.pid = pid; self.winId = winId; self.byPid = byPid; self.quiet = quiet; self.retry = retry
    }

    public static let everything = Selection()
}

/// Who's on screen right now: the front app and its front window, every other app.
public struct MenuContext: Equatable {
    public struct App: Equatable { public let pid: pid_t; public let name: String; public let count: Int }
    public var front: App?
    public var frontWin: UInt32?
    public var frontFrame: CGRect?
    public var total = 0
    public var others: [App] = []   // A–Z
}

/// The engine: moves windows, runs auto-restore, and keeps the retry offer.
/// A port of the Hammerspoon version's init.lua (everything but the UI).
/// All state lives on the main actor; every app call goes through a worker.
@MainActor
public final class Shepherd {
    public let system: WindowSystem
    public let store: LayoutStore
    public let frozenStore: FrozenStore
    /// The last screen change (persisted): the Revert row is for that combination.
    public internal(set) var lastChange: (key: String, at: Double)?
    public let book: LayoutBook
    let timing: MoveTiming
    var restoreTiming: RestoreTiming
    let now: () -> Date

    let runner = JobRunner()
    /// Bulk jobs and restores.
    let jobWorker = AXWorker(label: "jobs")

    public var onAlert: ((String) -> Void)?
    public var onBusyChanged: ((Bool) -> Void)?
    public internal(set) var isBusy = false
    public internal(set) var retryOffer: RetryOffer?

    /// Restore passes scheduled but not yet run (they keep the icon red).
    var pendingPasses = 0
    /// A restore your own move interrupted: run it again once the move is done.
    var resumeRestore = false
    var restoreTimers: [Int: Task<Void, Never>] = [:]
    var nextTimerID = 0
    /// Apps with a keyboard/menu snap in flight, and the latest press waiting behind it.
    var snapInFlight = Set<pid_t>()
    var snapPending: [pid_t: @MainActor () async -> Void] = [:]

    /// True while Accessibility is missing: the tick does nothing.
    public var paused = false

    public init(system: WindowSystem, store: LayoutStore, frozenStore: FrozenStore? = nil, timing: MoveTiming = .standard,
                restoreTiming: RestoreTiming = .standard, now: @escaping () -> Date = Date.init) {
        self.system = system
        self.store = store
        self.frozenStore = frozenStore ?? FrozenStore(url: FrozenStore.url(beside: store.url))
        self.timing = timing
        self.restoreTiming = restoreTiming
        self.now = now
        self.book = LayoutBook(layouts: store.load())
        runner.onBusyChanged = { [weak self] in self?.updateBusy() }
    }

    func updateBusy() {
        let busy = runner.current != nil || pendingPasses > 0
        guard busy != isBusy else { return }
        isBusy = busy
        onBusyChanged?(busy)
    }

    func alert(_ msg: String) {
        Log.info("alert: " + msg.replacingOccurrences(of: "\n", with: " / "))
        onAlert?(msg)
    }

    var nowSeconds: Double { now().timeIntervalSince1970 }

    // MARK: Moving windows

    /// pid → visible window ids (only these get moved).
    func windowIdsByPid(_ onlyPid: pid_t?) -> [pid_t: Set<UInt32>] {
        var by: [pid_t: Set<UInt32>] = [:]
        for w in system.visibleWindows() where onlyPid == nil || w.pid == onlyPid {
            by[w.pid, default: []].insert(w.id)
        }
        return by
    }

    /// Run `placer` on a selection of windows. Moved windows count as placed
    /// by you (a pending auto-restore leaves them alone) and are saved at
    /// once. Acting on a whole app brings that app to the front.
    public func apply(_ sel: Selection, placer: Placer, label: String) {
        let startSetup = book.lastSetup     // if the screens change mid-move, save nothing
        let screens = system.screens()
        let main = system.mainScreen()
        let tally = Tally<Bool>()
        if !sel.retry { retryOffer = nil }   // a new move replaces the old offer

        func finish(_ problem: JobProblem?) {
            tally.settle()
            let total = tally.moved
            let refused = tally.refused.values.reduce(0) { $0 + $1.count }
            // Keyboard single-window moves stay silent (like Rectangle) unless something went wrong.
            if !sel.quiet || !tally.skipped.isEmpty || problem != nil || total == 0 || refused > 0 {
                alert(reportText("Moved \(total) window\(total == 1 ? "" : "s") → \(label)",
                                 skipped: tally.skipped, hasMissed: !tally.missed.isEmpty, problem: problem, refused: refused))
            }
            if let pid = sel.pid, sel.winId == nil, problem != .interrupted {   // whole app: bring it forward
                let system = self.system
                Task { await AXWorker.detached { system.activate(pid: pid) } }
            }
            guard book.lastSetup == startSetup else { return }
            recordNow(tally.ids)
            if resumeRestore {
                resumeRestore = false
                schedulePass(after: 0.1)
                updateBusy()
            }
            if !tally.missed.isEmpty || sel.retry {
                offerRetry(.move, missed: tally.missed.mapValues { Set($0.keys) }) { [weak self] missed in
                    self?.apply(Selection(byPid: missed, retry: true), placer: placer, label: label)
                }
            }
        }

        if let winId = sel.winId, let pid = sel.pid {
            // One window: a single quick step outside the job runner, so a
            // keyboard snap never interrupts an auto-restore. Snaps for
            // different apps run side by side, so a hung app delays only its
            // own; repeated presses at one app collapse to the latest.
            // Not in the app's window list (the front "window" was a sheet)?
            // Use the app's focused window.
            let cgFrame = system.visibleWindows().first { $0.id == winId }?.frame
            let system = self.system
            runSnap(pid) { [weak self] in
                let moved: UInt32?? = await AXWorker.detached {
                    let wins = (try? system.appWindows(pid: pid)) ?? []
                    // The window with keyboard focus first: after ⌘` Chrome focuses a
                    // window without raising it, so the list's first one is the wrong one.
                    // Asked once; matched only on a real id (two unreadable ids aren't the same window).
                    let f = system.focusedWindow(pid: pid)
                    let focused = f.flatMap { $0.windowID }.flatMap { id in wins.first { $0.windowID == id } }
                    guard let target = focused ?? wins.first(where: { $0.windowID == winId }) ?? f,
                          let frame = target.frame() ?? cgFrame,
                          let r = placer.frame(for: frame, screens: screens, main: main),
                          (try? target.setFrame(r)) != nil else { return nil }
                    return .some(target.windowID)
                }
                guard let self else { return }
                if case let .some(id) = moved {
                    tally.moved = 1
                    // The screens changed meanwhile: it belongs to the old setup.
                    if let id, id != 0, self.book.lastSetup == startSetup {
                        tally.ids.insert(String(id))
                        self.book.restoredIds.insert(String(id))
                    }
                }
                finish(nil)
            }
            return
        }

        let byPid = sel.byPid ?? windowIdsByPid(sel.pid)
        let patientUntil = Date().addingTimeInterval(timing.movePatience)
        let steps: [JobStep] = byPid.keys.sorted().map { pid in
            appStep(pid: pid, wanted: Dictionary(uniqueKeysWithValues: byPid[pid]!.map { ($0, true) }),
                    system: system, worker: jobWorker, timing: timing, tally: tally, patientUntil: patientUntil,
                    gate: { [weak self] in self?.book.lastSetup == startSetup },   // screens changed: this target no longer exists
                    action: { win, _ in
                        guard let f = win.frame(), let r = placer.frame(for: f, screens: screens, main: main) else {
                            throw AXFailure(code: -25200)
                        }
                        try win.setFrame(r)
                    },
                    onMoved: { [weak self] id, _ in self?.book.restoredIds.insert(String(id)) })
        }
        let count = byPid.values.reduce(0) { $0 + $1.count }
        runner.run(.move, steps: steps, deadline: max(deadlineFor(windowCount: count), timing.movePatience + 10), done: finish)
    }

    /// At most one snap per app in flight; a newer press replaces any waiting one.
    func runSnap(_ pid: pid_t, _ work: @escaping @MainActor () async -> Void) {
        if snapInFlight.contains(pid) {
            snapPending[pid] = work
            return
        }
        snapInFlight.insert(pid)
        Task { @MainActor in
            await work()
            self.snapInFlight.remove(pid)
            if let next = self.snapPending.removeValue(forKey: pid) { self.runSnap(pid, next) }
        }
    }

    /// Save where just-moved windows are now (skips the two-sightings rule).
    func recordNow(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let screens = system.screens()
        book.recordNow(ids: ids, key: Screens.setupKey(screens), windows: system.visibleWindows(), screens: screens, now: nowSeconds)
        store.save(book.layouts)
    }

    /// The front app (whole app) or its front window; nil if no app is in front.
    func frontSel(wholeApp: Bool) -> Selection? {
        guard let pid = system.frontmostPID() else { return nil }
        if wholeApp { return Selection(pid: pid) }
        let first = system.visibleWindows().first { $0.pid == pid }   // front to back: its front window
        return Selection(pid: pid, winId: first?.id ?? 0, quiet: true)  // 0 = not listed: use the focused window
    }

    /// An action on the front window (or the whole front app), optionally on
    /// the screen after the one its front window is on.
    public func doAction(_ a: ActionID, wholeApp: Bool, nextScreen: Bool) {
        guard let sel = frontSel(wholeApp: wholeApp) else { return }
        var target = TargetScreen.own
        var label = a.rawValue
        if nextScreen && !wholeApp {
            target = .next
            label = a.rawValue + " on the next screen"
        } else if nextScreen {
            let screens = system.screens()
            let frame = system.visibleWindows().first { $0.pid == sel.pid }?.frame
            guard let here = frame.flatMap({ Geometry.screen(mostOf: $0, in: screens) }) ?? system.mainScreen() else { return }
            target = .fixed(uuid: Screens.next(after: here, in: screens).uuid)
            label = a.rawValue + " on the next screen"
        }
        apply(sel, placer: Placer(a.placement, on: target), label: label)
    }

    /// Screen n at its default size (laptop full, monitors 90%). More keys =
    /// more windows: this window / the front app / everything.
    public func toNumberedScreen(_ n: Int, scope: Scope) {
        let dests = Screens.destinations(system.screens())
        guard n >= 1, n <= dests.count else {
            alert("There's no screen \(n)")
            return
        }
        let dest = dests[n - 1]
        let f = Screens.defaultFraction(dest)
        let placer = Placer.fraction(f, on: .fixed(uuid: dest.screen.uuid))
        let label = "\(dest.name) (\(sizeLabel(f)))"
        switch scope {
        case .all: apply(.everything, placer: placer, label: label)
        case .app: apply(Selection(pid: system.frontmostPID() ?? -1), placer: placer, label: label)
        case .window:
            guard let sel = frontSel(wholeApp: false) else { return }
            apply(sel, placer: placer, label: label)
        }
    }

    public func menuContext() -> MenuContext {
        var ctx = MenuContext()
        let fpid = system.frontmostPID()
        var apps: [pid_t: (name: String, count: Int)] = [:]
        var order: [pid_t] = []
        for w in system.visibleWindows() {   // front to back
            ctx.total += 1
            if apps[w.pid] == nil {
                apps[w.pid] = (w.app, 0)
                order.append(w.pid)
                if w.pid == fpid { ctx.frontWin = w.id; ctx.frontFrame = w.frame }   // first seen = its front window
            }
            apps[w.pid]!.count += 1
        }
        if let fpid, let a = apps[fpid] { ctx.front = .init(pid: fpid, name: a.name, count: a.count) }
        ctx.others = order.filter { $0 != fpid }.map { MenuContext.App(pid: $0, name: apps[$0]!.name, count: apps[$0]!.count) }
            .sorted { $0.name < $1.name }
        return ctx
    }

    // MARK: Retry offer

    func offerRetry(_ kind: JobKind, missed: [pid_t: Set<UInt32>], run: @escaping @MainActor ([pid_t: Set<UInt32>]) -> Void) {
        if !missed.isEmpty {
            retryOffer = RetryOffer(kind: kind, at: now(), missed: missed, run: run)
        } else if retryOffer?.kind == kind {
            retryOffer = nil   // a later pass of the same kind got everything
        }
    }

    /// The retry offer's rows (sorted "App — Title"), or nil when there is
    /// none, or every window it lists has closed.
    public func retryRows() -> (count: Int, titles: [String])? {
        guard let offer = retryOffer else { return nil }
        var titles: [String] = []
        for w in system.visibleWindows() where offer.missed[w.pid]?.contains(w.id) == true {
            titles.append(retryTitle(app: w.app, title: w.title))
        }
        if titles.isEmpty { retryOffer = nil; return nil }
        return (titles.count, titles.sorted())
    }

    /// Run the retry offer the menu showed (`offerAt` = its time); a stale
    /// row does nothing. nil = whatever offer is current.
    public func runRetry(offerAt: Date? = nil) {
        guard let offer = retryOffer, offerAt == nil || offer.at == offerAt else { return }
        retryOffer = nil
        offer.run(offer.missed)
    }

    // MARK: Lifecycle (auto-restore orchestration is in Shepherd+Restore)

    /// At launch: no restore, just start remembering.
    public func start() {
        let saved = frozenStore.load()
        book.frozen = saved.copies
        if let k = saved.lastChangeKey, let at = saved.lastChangeAt { lastChange = (k, at) }
        book.prune(running: system.runningApps())
        let key = Screens.setupKey(system.screens())
        book.lastSetup = key
        book.snapshot(key: key, windows: system.visibleWindows(), screens: system.screens(), now: nowSeconds)
    }
}

public struct RestoreTiming {
    public var passes: [TimeInterval] = [3, 10, 20]
    public var busyRecheck: TimeInterval = 5
    public var unsettledLimit: TimeInterval = 60
    /// How long after a screen change a restore keeps retrying apps that are slow or refuse.
    public var patience: TimeInterval = 60

    public init(passes: [TimeInterval] = [3, 10, 20], busyRecheck: TimeInterval = 5, unsettledLimit: TimeInterval = 60,
                patience: TimeInterval = 60) {
        self.passes = passes; self.busyRecheck = busyRecheck; self.unsettledLimit = unsettledLimit; self.patience = patience
    }

    public static let standard = RestoreTiming()
}
