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
        func setFrame(_ r: CGRect) throws {
            let delay = sys.locked { sys.setDelay[id] ?? 0 }
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            if sys.locked({ sys.failSet.contains(id) }) { throw AXFailure(code: -25200) }
            sys.locked {
                sys.framesSet.append((id, r))
                if let i = sys.windows.firstIndex(where: { $0.id == id }) {
                    let w = sys.windows[i]
                    sys.windows[i] = CGWindow(id: w.id, pid: w.pid, app: w.app, title: w.title, frame: r)
                }
            }
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
    var listBehaviour: [pid_t: ListBehaviour] = [:]
    var hiddenFromAX: Set<UInt32> = []           // in the CG list but not in the app's AX list (sheets)
    var focused: [pid_t: UInt32] = [:]
    var unreadableIDs: Set<UInt32> = []          // _AXUIElementGetWindow fails for these
    var setDelay: [UInt32: TimeInterval] = [:]
    var failSet: Set<UInt32> = []                // setFrame throws for these
    var framesSet: [(UInt32, CGRect)] = []
    var activated: [pid_t] = []
    var listCalls: [pid_t: Int] = [:]
    var offSpace: Set<UInt32> = []
    var noFrame: Set<UInt32> = []                // frame() fails for these (the app didn't answer)               // exist (another Space, minimized) but aren't on screen

    var windowsByID: [UInt32: CGWindow] { Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) }) }

    func addApp(_ pid: pid_t, _ name: String, windows ws: [(UInt32, CGRect)], title: String? = "Doc") {
        locked {
            apps[pid] = name
            for (id, f) in ws { windows.append(CGWindow(id: id, pid: pid, app: name, title: title, frame: f)) }
        }
    }

    func frameOf(_ id: UInt32) -> CGRect? { locked { windowsByID[id]?.frame } }
    func setCount(_ id: UInt32) -> Int { locked { framesSet.filter { $0.0 == id }.count } }

    // MARK: WindowSystem
    func visibleWindows() -> [CGWindow] { locked { windows } }
    func allWindowIDs() -> Set<UInt32> { locked { Set(windows.map(\.id)).union(offSpace) } }
    func screens() -> [ScreenInfo] { locked { allScreens } }
    func mainScreen() -> ScreenInfo? { locked { main ?? allScreens.first } }
    func frontmostPID() -> pid_t? { locked { front } }
    func runningApps() -> [pid_t: String] { locked { apps } }
    func isRunning(bundleID: String) -> Bool { locked { bundles.contains(bundleID) } }
    func appName(pid: pid_t) -> String? { locked { apps[pid] } }

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
