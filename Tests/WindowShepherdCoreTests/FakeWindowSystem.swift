import XCTest
@testable import WindowShepherdCore

/// A scripted stand-in for macOS: apps, windows, screens, and how slow or
/// broken each app is. Thread-safe, because worker queues call into it.
final class FakeWindowSystem: WindowSystem {
    enum ListBehaviour { case ok, throwAlways, throwTimes(Int), sleep(TimeInterval) }

    final class Win: WindowHandle {
        let id: UInt32
        unowned let sys: FakeWindowSystem
        init(_ id: UInt32, _ sys: FakeWindowSystem) { self.id = id; self.sys = sys }
        var windowID: UInt32? { sys.locked { sys.unreadableIDs.contains(id) } ? nil : id }
        func frame() -> CGRect? { sys.locked { sys.noFrame.contains(id) ? nil : sys.windowsByID[id]?.frame } }
        var isStandard: Bool? { sys.locked { sys.unreadableKind.contains(id) ? nil : !sys.nonStandard.contains(id) } }
        var title: String? { sys.locked { sys.axTitles[id] } }
        var isFullScreen: Bool { sys.locked { sys.fullScreen.contains(id) } }
        var hasFullScreenButton: Bool { sys.locked { !sys.noFullScreenButton.contains(id) } }
        var isResizable: Bool { sys.locked { !sys.fixedSize.contains(id) } }
        func setFrame(_ r: CGRect) throws {
            // As AXWindow does: an app with enhanced UI on has it switched off for the move, then on.
            if let pid = sys.locked({ sys.windowsByID[id]?.pid }), sys.enhancedUIOff(pid: pid) {
                defer { sys.enhancedUIOn(pid: pid) }
                try move(r)
                return
            }
            try move(r)
        }
        private func move(_ r: CGRect) throws {
            let delay = sys.locked { sys.setDelay[id] ?? 0 }
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            if sys.locked({ sys.failSet.contains(id) }) { throw AXFailure(code: -25200) }
            sys.locked {
                sys.framesSet.append((id, r))
                if let i = sys.windows.firstIndex(where: { $0.id == id }) {
                    let w = sys.windows[i]
                    if sys.staleFrameOnce.remove(id) != nil { sys.staleFrames[id] = w.frame }
                    let fixed = sys.fixedSize.contains(id)   // a fixed-size window moves but keeps its size
                    var f = fixed ? CGRect(origin: r.origin, size: w.frame.size) : r
                    if sys.ignorePosition.contains(id) { f.origin = w.frame.origin }          // took the size, not the position
                    if let cap = sys.shrinkHeight[id] { f.size.height = min(f.height, cap) }   // resizable, but no taller than this
                    sys.windows[i] = CGWindow(id: w.id, pid: w.pid, app: w.app, title: w.title, frame: f)
                }
            }
            let reply = sys.locked { sys.replyDelay[id] ?? 0 }   // moved at once, but the app answers late
            if reply > 0 { Thread.sleep(forTimeInterval: reply) }
        }
    }

    private let lock = NSRecursiveLock()
    func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    var windows: [CGWindow] = []                 // front to back
    var allScreens: [ScreenInfo] = [screen(1, "Built-in", x: 0, builtin: true)]
    var main: ScreenInfo?
    var front: pid_t?
    var apps: [pid_t: String] = [:]
    var bundles: Set<String> = []
    var bundleOf: [pid_t: String] = [:]
    var launched: [pid_t: Date] = [:]
    var nonStandard: Set<UInt32> = []            // subrole isn't standard (dialogs, palettes)
    var unreadableKind: Set<UInt32> = []         // the subrole can't be read (isStandard nil)
    var noFullScreenButton: Set<UInt32> = []     // no green full-screen button (Finder's Get Info, Photoshop documents)
    var staleFrameOnce: Set<UInt32> = []         // the next window list after a setFrame still shows the old frame
    var staleFrames: [UInt32: CGRect] = [:]
    var bundleByName: [String: String] = [:]     // apps that aren't running, found by name
    var fixedSize: Set<UInt32> = []              // size can't change
    var ignorePosition: Set<UInt32> = []         // setFrame succeeds but the window stays where it was
    var shrinkHeight: [UInt32: CGFloat] = [:]    // setFrame succeeds but the height is capped
    var listBehaviour: [pid_t: ListBehaviour] = [:]
    var hiddenFromAX: Set<UInt32> = []           // in the CG list but not in the app's AX list (sheets)
    var focused: [pid_t: UInt32] = [:]
    var unreadableIDs: Set<UInt32> = []          // _AXUIElementGetWindow fails for these
    var setDelay: [UInt32: TimeInterval] = [:]
    var replyDelay: [UInt32: TimeInterval] = [:]  // setFrame moves the window, then returns this much later
    var failSet: Set<UInt32> = []                // setFrame throws for these
    var framesSet: [(UInt32, CGRect)] = []
    var activated: [pid_t] = []
    var listCalls: [pid_t: Int] = [:]
    var offSpace: Set<UInt32> = []
    var mouseUsed: Date?                         // the last left-button press or drag
    var mouseDragged: Date?                      // the last left-button drag
    var fullScreen: Set<UInt32> = []             // in native full screen (its own Space)
    var axTitles: [UInt32: String] = [:]         // titles the app reports (Accessibility)
    var allIDsReads = 0                          // full window-list reads (.optionAll: costly)
    var enhancedUI: Set<pid_t> = []              // apps with AXEnhancedUserInterface on (Chrome under assistive tools)
    var enhancedOffCount: [pid_t: Int] = [:]     // times it was switched off
    var noFrame: Set<UInt32> = []                // frame() fails for these (the app didn't answer)               // exist (another Space, minimized) but aren't on screen

    var windowsByID: [UInt32: CGWindow] { Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) }) }

    func addApp(_ pid: pid_t, _ name: String, windows ws: [(UInt32, CGRect)], title: String? = "Doc", bundle: String? = nil) {
        locked {
            apps[pid] = name
            bundleOf[pid] = bundle ?? "test." + name
            for (id, f) in ws { windows.append(CGWindow(id: id, pid: pid, app: name, title: title, frame: f)) }
        }
    }

    func frameOf(_ id: UInt32) -> CGRect? { locked { windowsByID[id]?.frame } }
    func setCount(_ id: UInt32) -> Int { locked { framesSet.filter { $0.0 == id }.count } }

    // MARK: WindowSystem
    func visibleWindows() -> [CGWindow] {
        locked {
            guard !staleFrames.isEmpty else { return windows }
            defer { staleFrames = [:] }
            return windows.map { w in staleFrames[w.id].map { CGWindow(id: w.id, pid: w.pid, app: w.app, title: w.title, frame: $0) } ?? w }
        }
    }
    func allWindowIDs() -> Set<UInt32> { locked { allIDsReads += 1; return Set(windows.map(\.id)).union(offSpace) } }
    func screens() -> [ScreenInfo] { locked { allScreens } }
    func mainScreen() -> ScreenInfo? { locked { main ?? allScreens.first } }
    func frontmostPID() -> pid_t? { locked { front } }
    func runningApps() -> [pid_t: String] { locked { apps } }
    func isRunning(bundleID: String) -> Bool { locked { bundles.contains(bundleID) } }
    func appName(pid: pid_t) -> String? { locked { apps[pid] } }
    func bundleID(pid: pid_t) -> String? { locked { bundleOf[pid] } }
    func bundleID(appName: String) -> String? {
        locked { apps.first { $0.value == appName }.flatMap { bundleOf[$0.key] } ?? bundleByName[appName] }
    }
    func launchDate(pid: pid_t) -> Date? { locked { launched[pid] } }
    func lastMouseUse() -> Date? { locked { mouseUsed } }
    func lastMouseDrag() -> Date? { locked { mouseDragged } }
    func enhancedUIOff(pid: pid_t) -> Bool {
        locked {
            guard enhancedUI.remove(pid) != nil else { return false }
            enhancedOffCount[pid, default: 0] += 1
            return true
        }
    }
    func enhancedUIOn(pid: pid_t) { _ = locked { enhancedUI.insert(pid) } }

    func appWindows(pid: pid_t) throws -> [WindowHandle] {
        let behaviour: ListBehaviour = locked {
            listCalls[pid, default: 0] += 1
            return listBehaviour[pid] ?? .ok
        }
        switch behaviour {
        case .ok: break
        case .throwAlways: throw AXFailure(code: -25204)
        case .throwTimes(let n):
            if locked({ listCalls[pid]! }) <= n { throw AXFailure(code: -25204) }
        case .sleep(let t): Thread.sleep(forTimeInterval: t)
        }
        return locked { windows.filter { $0.pid == pid && !hiddenFromAX.contains($0.id) }.map { Win($0.id, self) } }
    }

    func focusedWindow(pid: pid_t) -> WindowHandle? {
        locked { focused[pid].map { Win($0, self) } }
    }

    func activate(pid: pid_t) { locked { activated.append(pid) } }
}

@MainActor
func waitUntil(_ timeout: TimeInterval = 3, _ cond: @escaping () -> Bool) async {
    let end = Date().addingTimeInterval(timeout)
    while !cond() && Date() < end { try? await Task.sleep(nanoseconds: 5_000_000) }
}
