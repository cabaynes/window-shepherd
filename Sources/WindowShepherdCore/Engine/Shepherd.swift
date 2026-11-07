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
    public let spotStore: AppSpotStore
    /// Per setup and app, where its windows have been (see AppSpotBook).
    public let spots: AppSpotBook
    /// The last screen change (persisted): the Revert row is for that combination.
    public internal(set) var lastChange: (key: String, at: Double)?
    public let book: LayoutBook
    let timing: MoveTiming
    var restoreTiming: RestoreTiming
    let now: () -> Date

    let runner = JobRunner()
    /// Bulk jobs and restores.
    let jobWorker = AXWorker(label: "jobs")
    /// Learns which windows are main windows; apart from `jobWorker` so restores never wait on it.
    let kindWorker = AXWorker(label: "kinds")
    /// Window id → is a main window (not a dialog, settings window or panel). Runtime only.
    var kinds: [String: Bool] = [:]
    /// Apps with a kind request in flight, and how often each window came back unreadable.
    var kindsInFlight = Set<pid_t>()
    var kindMisses: [String: Int] = [:]
    /// How often each window was missing from its app's own (fully read) window list.
    var kindAbsences: [String: Int] = [:]
    /// When the Mac last woke (a guessing period follows).
    var wokeAt: Double?
    /// App spots changed since the last save (saved at most once per tick).
    var spotsDirty = false
    /// Window id → the spot it held before its latest record (nil = none) and when, kept briefly
    /// so a move that didn't land can be undone.
    var lastRecorded: [String: (spot: AppSpot?, at: Double)] = [:]
    /// Window id → when a restore put it in a free app spot (it took the hold then), kept
    /// briefly so a move that didn't land leaves the spot free.
    var heldByRestore: [String: Double] = [:]
    /// What each move asked for, checked a couple of seconds later (`checkLandings`).
    let landing = Landing()
    /// When the last two settled snapshots ran, oldest first (real time, like `lastMouseUse`).
    var snapshotTimes: [Date] = []
    /// New windows seen once and not placed yet: where, and when (real time, like `lastMouseUse`).
    /// Neither in this setup's per-window layout nor holding a spot. Runtime only.
    var firstSeen: [String: (at: Spot, tick: Double)] = [:]
    /// Of those: ticks spent waiting for the kind, and when each was ready while a job ran.
    var newKindWaits: [String: Int] = [:]
    var newReadyAt: [String: Double] = [:]
    /// Of those: how often the app moved it before it settled.
    var newResets: [String: Int] = [:]
    /// Windows never placed as new: open before they could be, or left once. Runtime only.
    var notNew = Set<String>()
    /// New windows you dragged before they could be placed: their first recording becomes a spot.
    var draggedNew = Set<String>()
    /// The window list at the last new-window sighting (to tell a tab switch from a new window).
    var previousSighting: [CGWindow] = []
    /// The running placement's setup and the windows it gave a spot but hasn't moved yet.
    var placing: (key: String, pending: Set<String>)?

    public var onAlert: ((String) -> Void)?
    public var onBusyChanged: ((Bool) -> Void)?
    public internal(set) var isBusy = false
    public internal(set) var retryOffer: RetryOffer? {
        didSet { if let o = retryOffer { fetchRetryTitles(o.missed) } }
    }
    /// Titles of windows in the Retry row, read through Accessibility (the window list has
    /// none without Screen Recording). Filled in the background when an offer is made.
    var axTitles: [UInt32: String] = [:]
    /// A restore left windows behind and you haven't opened the menu since.
    public internal(set) var flashing = false
    public var onFlashChanged: ((Bool) -> Void)?

    /// Restore passes scheduled but not yet run (they keep the icon red).
    var pendingPasses = 0
    /// A restore your own move interrupted: run it again once the move is done.
    var resumeRestore = false
    /// A Revert that hasn't run yet (it waited for another job, or your move interrupted it):
    /// when its patience ends (engine clock), a full patience from when you pressed it.
    var revertPending: Double?
    /// Where each window opened while undocked was at the last screen change, and when (real
    /// time, to compare with mouse drags): one dragged since is yours, not the undocked default's.
    var homelessAt: [String: Spot?] = [:]
    var changedAtDate = Date.distantPast
    /// The window list at the last settled tick (to tell a tab switch from a window coming back).
    var lastTickWindows: [CGWindow] = []
    var restoreTimers: [Int: Task<Void, Never>] = [:]
    var nextTimerID = 0
    /// Apps with a keyboard/menu snap in flight, and the latest press waiting behind it.
    var snapInFlight = Set<pid_t>()
    var snapPending: [pid_t: @MainActor () async -> Void] = [:]
    /// Per app, the windows its in-flight or waiting snaps were pressed on: yours from the
    /// press, since the app can move a window well before it answers.
    var snapping: [pid_t: Set<UInt32>] = [:]

    /// Where windows opened while a screen was unplugged go when it's back.
    public var undocked = UndockedWindows.defaults

    /// True while Accessibility is missing: the tick does nothing.
    public var paused = false

    public init(system: WindowSystem, store: LayoutStore, frozenStore: FrozenStore? = nil, spotStore: AppSpotStore? = nil, timing: MoveTiming = .standard,
                restoreTiming: RestoreTiming = .standard, now: @escaping () -> Date = Date.init) {
        self.system = system
        self.store = store
        self.frozenStore = frozenStore ?? FrozenStore(url: FrozenStore.url(beside: store.url))
        self.spotStore = spotStore ?? AppSpotStore(url: AppSpotStore.url(beside: store.url))
        self.spots = AppSpotBook(spots: [:])
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
    /// once. Acting on a whole app brings that app to the front. `then` runs once it's done,
    /// unless a newer move interrupted it.
    public func apply(_ sel: Selection, placer: Placer, label: String, then: (@MainActor () -> Void)? = nil) {
        let startSetup = book.lastSetup     // if the screens change mid-move, save nothing
        let screens = system.screens()
        let main = system.mainScreen()
        let tally = Tally<UInt32>()
        let landing = self.landing, clock = landingClock
        if !sel.retry { retryOffer = nil }   // a new move replaces the old offer

        var inFullScreen = false   // a snap's window was in full screen: say that instead
        var fullScreenCount = 0    // a bulk move's windows left alone in full screen
        func finish(_ problem: JobProblem?) {
            defer { if problem != .interrupted { then?() } }
            tally.settle()
            let total = tally.moved
            let refused = tally.refused.values.reduce(0) { $0 + $1.count }
            // Keyboard single-window moves stay silent (like Rectangle) unless something went wrong.
            if inFullScreen {
                alert("That window is in full screen, so Window Shepherd leaves it where it is")
            } else if !sel.quiet || !tally.skipped.isEmpty || problem != nil || total == 0 || refused > 0 {
                var msg = reportText("Moved \(total) window\(total == 1 ? "" : "s") → \(label)",
                                     skipped: tally.skipped, hasMissed: !tally.missed.isEmpty, problem: problem, refused: refused)
                if fullScreenCount > 0 {
                    msg += "\n(\(fullScreenCount) in full screen, left as \(fullScreenCount == 1 ? "it is" : "they are"))"
                }
                alert(msg)
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
                offerRetry(.move, missed: tally.missed.mapValues { Set($0.keys) }, retry: .move(placer, label)) { [weak self] missed in
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
            if winId != 0 { snapping[pid, default: []].insert(winId) }
            runSnap(pid) { [weak self] in
                let outcome: SnapOutcome = await AXWorker.detached {
                    let wins = (try? system.appWindows(pid: pid)) ?? []
                    // The window with keyboard focus first: after ⌘` Chrome focuses a
                    // window without raising it, so the list's first one is the wrong one.
                    // Asked once; matched only on a real id (two unreadable ids aren't the same window).
                    let f = system.focusedWindow(pid: pid)
                    let focused = f.flatMap { $0.windowID }.flatMap { id in wins.first { $0.windowID == id } }
                    guard let target = focused ?? wins.first(where: { $0.windowID == winId }) ?? f,
                          let frame = target.frame() ?? cgFrame else { return .noAnswer }
                    if target.isFullScreen { return .fullScreen }
                    guard let r = placer.frame(for: frame, screens: screens, main: main) else { return .nothingToDo }
                    guard (try? target.setFrame(r)) != nil else { return .refused }
                    let id = target.windowID
                    if let id, id != 0 {
                        landing.expect(.init(pid: pid, id: id, wanted: r, resizable: target.isResizable, at: clock(),
                                             retry: .move(placer, label)))
                    }
                    return .moved(id)
                }
                guard let self else { return }
                switch outcome {
                case let .moved(id):
                    tally.moved = 1
                    // The screens changed meanwhile: it belongs to the old setup.
                    if let id, id != 0, self.book.lastSetup == startSetup {
                        tally.ids.insert(String(id))
                        self.book.restoredIds.insert(String(id))
                    }
                case .noAnswer:   // name the app, and offer Retry
                    tally.skipped.append(self.system.appName(pid: pid) ?? "the app")
                    if winId != 0 { tally.missed[pid] = [winId: winId] }
                case .refused:
                    if winId != 0 {
                        tally.refused[pid] = [winId: winId]
                        tally.missed[pid] = [winId: winId]
                    }
                case .nothingToDo:
                    break
                case .fullScreen:   // its own Space: left alone, and said why (not "Moved 0 windows")
                    inFullScreen = true
                }
                finish(nil)
            }
            return
        }

        let byPid = sel.byPid ?? windowIdsByPid(sel.pid)
        let patientUntil = Date().addingTimeInterval(timing.movePatience)
        let steps: [JobStep] = byPid.keys.sorted().map { pid in
            appStep(pid: pid, wanted: Dictionary(uniqueKeysWithValues: byPid[pid]!.map { ($0, $0) }),
                    system: system, worker: jobWorker, timing: timing, tally: tally, patientUntil: patientUntil,
                    gate: { [weak self] in self?.book.lastSetup == startSetup },   // screens changed: this target no longer exists
                    action: { win, id in
                        guard let f = win.frame(), let r = placer.frame(for: f, screens: screens, main: main) else {
                            throw AXFailure(code: -25200)
                        }
                        try win.setFrame(r)
                        landing.expect(.init(pid: pid, id: id, wanted: r, resizable: win.isResizable, at: clock(),
                                             retry: .move(placer, label)))
                    },
                    onMoved: { [weak self] id, _ in self?.book.restoredIds.insert(String(id)) },
                    onFullScreen: { _ in fullScreenCount += 1 })
        }
        let count = byPid.values.reduce(0) { $0 + $1.count }
        runner.run(.move, steps: steps, deadline: max(deadlineFor(windowCount: count), timing.movePatience + 10), done: finish)
    }

    /// How a keyboard snap went: moved (its window id, if readable), the app didn't answer
    /// (no window or frame read), it refused the move, or the placer had nothing to do.
    enum SnapOutcome { case moved(UInt32?), noAnswer, refused, nothingToDo, fullScreen }

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
            if let next = self.snapPending.removeValue(forKey: pid) { self.runSnap(pid, next) } else { self.snapping[pid] = nil }
        }
    }

    /// Save where just-moved windows are now (skips the two-sightings rule).
    func recordNow(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let screens = system.screens()
        let key = Screens.setupKey(screens)
        let windows = system.visibleWindows()
        book.recordNow(ids: ids, key: key, windows: windows, screens: screens, now: nowSeconds)
        store.save(book.layouts)
        guard key == book.lastSetup else { return }
        for w in windows where ids.contains(String(w.id)) { recordSpot(w, key: key, screens: screens) }
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

    func offerRetry(_ kind: JobKind, missed: [pid_t: Set<UInt32>], retry: Landing.Retry? = nil,
                    run: @escaping @MainActor ([pid_t: Set<UInt32>]) -> Void) {
        if !missed.isEmpty {
            retryOffer = RetryOffer(kind: kind, at: now(), missed: missed, run: run, retry: retry)
        } else if let old = retryOffer, old.kind == kind {
            // A later pass of the same kind got everything, except windows still left behind
            // (a move that didn't land): those stay offered.
            var kept: [pid_t: Set<UInt32>] = [:]
            for (pid, ids) in old.missed {
                let still = ids.filter { book.leftBehind.contains(String($0)) }
                if !still.isEmpty { kept[pid] = still }
            }
            retryOffer = kept.isEmpty ? nil : RetryOffer(kind: old.kind, at: old.at, missed: kept, run: old.run, retry: old.retry)
        }
    }

    /// Reads the titles of an offer's windows off the main thread (an app that doesn't
    /// answer costs only its own timeout there); the menu uses them when it next opens.
    func fetchRetryTitles(_ missed: [pid_t: Set<UInt32>]) {
        let want = missed.mapValues { $0.filter { axTitles[$0] == nil } }.filter { !$0.value.isEmpty }
        guard !want.isEmpty else { return }
        let system = self.system
        Task { @MainActor [weak self] in
            let got: [UInt32: String] = await AXWorker.detached {
                var out: [UInt32: String] = [:]
                for (pid, ids) in want {
                    guard let wins = try? system.appWindows(pid: pid) else { continue }
                    for w in wins {
                        if let id = w.windowID, ids.contains(id), let t = w.title, !t.isEmpty { out[id] = t }
                    }
                }
                return out
            }
            self?.axTitles.merge(got) { _, new in new }
        }
    }

    /// The retry offer's rows (sorted "App — Title"), or nil when there is
    /// none, or every window it lists has closed.
    public func retryRows() -> (count: Int, titles: [String])? {
        guard let offer = retryOffer else { return nil }
        var titles: [String] = []
        for w in system.visibleWindows() where offer.missed[w.pid]?.contains(w.id) == true {
            titles.append(retryTitle(app: w.app, title: w.title?.isEmpty == false ? w.title : axTitles[w.id]))
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

    /// Forget closed windows; frozen copies that lost some are saved now, not at the next screen change.
    @discardableResult
    func forgetClosed(existing: Set<UInt32>, running: Set<pid_t>) -> Bool {
        let frozenBefore = book.frozen
        let dropped = book.forgetClosed(existing: existing, running: running)
        if book.frozen != frozenBefore {
            frozenStore.save(FrozenState(copies: book.frozen, lastChangeKey: lastChange?.key, lastChangeAt: lastChange?.at))
        }
        return dropped
    }

    /// At launch: no restore, just start remembering.
    public func start() {
        let saved = frozenStore.load()
        book.frozen = saved.copies
        if let k = saved.lastChangeKey, let at = saved.lastChangeAt { lastChange = (k, at) }
        let running = system.runningApps()
        if let loaded = spotStore.load() {
            spots.spots = loaded
        } else {
            var bundleByName: [String: String?] = [:]   // looked up once per app, not per entry
            let seeded = AppSpotBook.seed(layouts: book.layouts, frozen: book.frozen, bundleFor: { [system] e in
                if let known = bundleByName[e.app] { return known }
                let bundle = running[pid_t(e.pid)] == e.app ? system.bundleID(pid: pid_t(e.pid)) : system.bundleID(appName: e.app)
                bundleByName.updateValue(bundle, forKey: e.app)
                return bundle
            }, now: nowSeconds)
            spots.spots = seeded
            spotStore.save(seeded)
            let n = seeded.values.flatMap { $0.values }.map(\.count).reduce(0, +)
            let apps = Set(seeded.values.flatMap { $0.keys }).count
            Log.info("app spots: seeded \(n) spots for \(apps) apps from the remembered layouts")
        }
        book.prune(running: running)
        holdOpenWindows()
        let key = Screens.setupKey(system.screens())
        book.lastSetup = key
        noteNewAtStart(key: key)
        book.snapshot(key: key, windows: system.visibleWindows(), screens: system.screens(), now: nowSeconds)
        noteSnapshot()
    }
}

public struct RestoreTiming {
    public var passes: [TimeInterval] = [3, 10, 20]
    public var busyRecheck: TimeInterval = 5
    public var unsettledLimit: TimeInterval = 60
    /// How long after a screen change a restore keeps retrying apps that are slow or refuse.
    public var patience: TimeInterval = 60
    /// How long after a screen change a window that was off screen is put back when it shows up.
    public var offscreenFor: TimeInterval = 600
    /// How long after an app launches, a screen change or a wake a window that moves
    /// by itself is taken for macOS's or the app's guess, not your placement.
    public var guessing: TimeInterval = 60

    public init(passes: [TimeInterval] = [3, 10, 20], busyRecheck: TimeInterval = 5, unsettledLimit: TimeInterval = 60,
                patience: TimeInterval = 60, guessing: TimeInterval = 60) {
        self.passes = passes; self.busyRecheck = busyRecheck; self.unsettledLimit = unsettledLimit; self.patience = patience
        self.guessing = guessing
    }

    public static let standard = RestoreTiming()
}
