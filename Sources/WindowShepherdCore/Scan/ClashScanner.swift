import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// macOS's own shortcuts (Spotlight, Mission Control, screenshots…) that are
/// switched on, which would take a key before Window Shepherd sees it.
public enum SystemShortcuts {
    public static func combo(code: Int, carbonMods: UInt32) -> Combo? {
        guard code >= 0, code < 0xFFFF, let key = KeyCodes.name(for: UInt16(code)) else { return nil }
        return Combo(mods: mods(fromCarbon: carbonMods), key: key)
    }

    /// The enabled system shortcuts, from Carbon's CopySymbolicHotKeys (fast, no app calls).
    public static func enabled() -> [Combo] {
        var ref: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&ref) == noErr, let list = ref?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard (d[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = (d[kHISymbolicHotKeyCode as String] as? NSNumber)?.intValue,
                  let m = (d[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value else { return nil }
            return combo(code: code, carbonMods: m)
        }
    }

    /// Names for the shortcuts the user changed (the symbolichotkeys
    /// preferences list only those): combo id → name.
    public static func changedNames() -> [String: String] {
        guard let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") else { return [:] }
        var names: [String: String] = [:]
        for (id, raw) in all {
            guard let e = raw as? [String: Any], (e["enabled"] as? Bool) == true,
                  let value = e["value"] as? [String: Any], let p = value["parameters"] as? [Int], p.count >= 3,
                  p[1] != 65535, let key = KeyCodes.name(for: UInt16(p[1])),
                  let c = Conflicts.fromSymbolic(keyName: key, flags: p[2]) else { continue }
            names[c.id] = Int(id).flatMap { KnownShortcuts.shared.system[$0] } ?? "a macOS shortcut"
        }
        return names
    }

    public static func match(combos: [Combo], enabled: [Combo], changedNames: [String: String]) -> [SystemShortcut] {
        let on = Set(enabled.map(\.id))
        return combos.filter { on.contains($0.id) }.map {
            SystemShortcut(combo: $0, name: changedNames[$0.id] ?? SystemShortcutNames.defaultName(for: $0) ?? "a macOS shortcut")
        }
    }

    /// macOS shortcuts that would take any of `combos` first.
    public static func entries(for combos: [Combo]) -> [SystemShortcut] {
        match(combos: combos, enabled: enabled(), changedNames: changedNames())
    }
}

/// Custom app shortcuts set in System Settings → Keyboard → App Shortcuts.
public enum UserKeyEquivalents {
    public static func parse(_ dict: [String: Any], app: String) -> [AppShortcut] {
        dict.compactMap { title, value in
            guard let s = value as? String, let c = Conflicts.fromUserKeyEquivalent(s) else { return nil }
            return AppShortcut(combo: c, app: app, what: title)
        }.sorted { $0.what < $1.what }
    }

    public static func all(running: [(id: String, name: String)]) -> [AppShortcut] {
        var out: [AppShortcut] = []
        if let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["NSUserKeyEquivalents"] as? [String: Any] {
            out += parse(global, app: "All apps (your custom shortcut)")
        }
        for app in running {
            if let d = UserDefaults(suiteName: app.id)?.dictionary(forKey: "NSUserKeyEquivalents") {
                out += parse(d, app: app.name + " (your custom shortcut)")
            }
        }
        return out
    }
}

/// One menu item's details, read in a single call.
public struct MenuRead {
    public let title: String?
    public let cmdChar: String?
    public let mods: Int?
    public let glyph: Int?
    public let children: [AnyObject]

    public init(title: String?, cmdChar: String?, mods: Int?, glyph: Int?, children: [AnyObject]) {
        self.title = title; self.cmdChar = cmdChar; self.mods = mods; self.glyph = glyph; self.children = children
    }
}

/// Reads app menus. Background thread only: every call may wait on the app.
public protocol MenuReader {
    func menuBar(pid: pid_t) throws -> AnyObject?
    func read(_ element: AnyObject) throws -> MenuRead
}

public struct AXMenuReader: MenuReader {
    private static let attrs = ["AXTitle", "AXMenuItemCmdChar", "AXMenuItemCmdModifiers", "AXMenuItemCmdGlyph", "AXChildren"] as CFArray

    public init() {}

    public func menuBar(pid: pid_t) throws -> AnyObject? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, "AXMenuBar" as CFString, &ref)
        guard err == .success, let v = ref, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return v
    }

    public func read(_ element: AnyObject) throws -> MenuRead {
        let e = element as! AXUIElement
        AXUIElementSetMessagingTimeout(e, axTimeout)
        var ref: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(e, Self.attrs, AXCopyMultipleAttributeOptions(rawValue: 0), &ref)
        guard err == .success, let values = ref as? [AnyObject], values.count == 5 else { throw AXFailure(code: err.rawValue) }
        func string(_ v: AnyObject) -> String? { v as? String }
        func int(_ v: AnyObject) -> Int? { (v as? NSNumber)?.intValue }
        let kids = (values[4] as? [AnyObject]) ?? []
        return MenuRead(title: string(values[0]), cmdChar: string(values[1]), mods: int(values[2]), glyph: int(values[3]),
                        children: kids.filter { CFGetTypeID($0) == AXUIElementGetTypeID() })
    }
}

public final class ScanHandle {
    private let lock = NSLock()
    private var _stopped = false
    public var stopped: Bool { lock.lock(); defer { lock.unlock() }; return _stopped }
    public func stop() { lock.lock(); _stopped = true; lock.unlock() }
}

/// Gathers what other software uses, for the Customize Shortcuts window:
/// macOS shortcuts, custom app shortcuts, the built-in list, and the menus
/// of every open app. Hard rule: nothing may hang. Menus are walked on a
/// background queue, one app at a time; any single read slower than
/// `slowCall`, or an app over `appLimit` in all, skips the rest of that app.
public final class ClashScanner {
    public struct Limits {
        public var slowCall: TimeInterval = 0.4
        public var appLimit: TimeInterval = 3
        /// Menu bar item 1, its menu 2, items 3, a submenu 4, its items 5, a
        /// sub-submenu 6. Deeper lists rarely carry shortcuts and cost the most.
        public var maxDepth = 6
        public init() {}
    }

    private let limits: Limits
    private let reader: MenuReader
    private let queue = DispatchQueue(label: "window-shepherd.scan", qos: .utility)

    public init(limits: Limits = .init(), menuReader: MenuReader = AXMenuReader()) {
        self.limits = limits
        self.reader = menuReader
    }

    /// The regular apps running now, except Window Shepherd itself.
    @MainActor public static func regularApps() -> [(pid: pid_t, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .map { (pid: $0.processIdentifier, name: $0.localizedName ?? "?") }
    }

    /// Start a scan. `onUpdate(sources, done, total)` runs after each app,
    /// `onDone(sources)` at the end, both on the main actor.
    @MainActor
    public func start(combos: [Combo], apps: [(pid: pid_t, name: String)]? = nil,
                      onUpdate: @escaping @MainActor (ClashSources, Int, Int) -> Void,
                      onDone: @escaping @MainActor (ClashSources) -> Void) -> ScanHandle {
        let handle = ScanHandle()
        let apps = apps ?? Self.regularApps()
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .compactMap { a in a.bundleIdentifier.map { (id: $0, name: a.localizedName ?? $0) } }
        var sources = ClashSources(system: SystemShortcuts.entries(for: combos),
                                   apps: KnownShortcuts.shared.apps + UserKeyEquivalents.all(running: running))
        onUpdate(sources, 0, apps.count)
        let reader = self.reader, limits = self.limits
        queue.async {
            for (i, app) in apps.enumerated() {
                if handle.stopped { return }
                let found = Self.walk(app, reader: reader, limits: limits, handle: handle)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard !handle.stopped else { return }
                        sources.apps += found
                        onUpdate(sources, i + 1, apps.count)
                    }
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard !handle.stopped else { return }
                    onDone(sources)
                }
            }
        }
        return handle
    }

    private static func walk(_ app: (pid: pid_t, name: String), reader: MenuReader, limits: Limits, handle: ScanHandle) -> [AppShortcut] {
        let started = Date()
        func timed<T>(_ body: () throws -> T) -> (T?, TimeInterval) {
            let t = Date()
            let v = try? body()
            return (v, Date().timeIntervalSince(t))
        }
        let (barOpt, took) = timed { try reader.menuBar(pid: app.pid) }
        guard let bar = barOpt ?? nil, took <= limits.slowCall else {
            if took > limits.slowCall { Log.info(String(format: "menu scan: %@ answered slowly (%.2fs), skipped", app.name, took)) }
            return []
        }
        let (barRead, took2) = timed { try reader.read(bar) }
        guard let top = barRead, took2 <= limits.slowCall else {
            if took2 > limits.slowCall { Log.info(String(format: "menu scan: %@ answered slowly (%.2fs), skipped", app.name, took2)) }
            return []
        }
        var out: [AppShortcut] = []
        var stack: [(AnyObject, Int)] = top.children.map { ($0, 1) }
        while let (el, depth) = stack.popLast() {
            if handle.stopped { return out }
            let (r, t) = timed { try reader.read(el) }
            if t > limits.slowCall || Date().timeIntervalSince(started) > limits.appLimit {
                Log.info("menu scan: \(app.name) too slow, skipped the rest of its menus")
                break
            }
            guard let r else { continue }
            if let c = Conflicts.fromAXMenu(cmdChar: r.cmdChar, modifiers: r.mods, glyph: r.glyph),
               let title = r.title, !title.isEmpty {
                out.append(AppShortcut(combo: c, app: app.name, what: title))
            }
            if depth < limits.maxDepth { stack += r.children.map { ($0, depth + 1) } }
        }
        return out
    }
}
