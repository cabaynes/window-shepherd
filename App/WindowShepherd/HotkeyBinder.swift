import AppKit
import WindowShepherdCore

/// Binds every Window Shepherd shortcut from the config. ⌥⌘ + key = this
/// window; add ⌃ = every window of the front app; add ⇧ = on the next
/// screen. Screen keys are bound only for screens that exist (and only with
/// 2+), so apps keep the other numbers. Action keys switch off while
/// Rectangle runs; number keys and the menu key stay on.
@MainActor
final class HotkeyBinder {
    nonisolated static let rectangleID = "com.knollsoft.Rectangle"

    private let shepherd: Shepherd
    private let store: ShortcutStore
    private let openMenuAtMouse: () -> Void

    private(set) var config: ShortcutConfig
    private(set) var bindings: [ShortcutBinding]
    private var windowKeys: [Hotkey] = []
    private var numberKeys: [Hotkey] = []
    private var menuKey: Hotkey?
    private var numberKeyCount = -1
    private(set) var suspended = false
    private(set) var windowKeysOn: Bool
    /// False while Accessibility is missing: nothing is registered.
    var active = false { didSet { if active != oldValue { apply(config, save: false) } } }

    init(shepherd: Shepherd, store: ShortcutStore, openMenuAtMouse: @escaping () -> Void) {
        self.shepherd = shepherd
        self.store = store
        self.openMenuAtMouse = openMenuAtMouse
        config = store.load()
        bindings = derive(config)
        windowKeysOn = !shepherd.system.isRunning(bundleID: Self.rectangleID)
        Log.info(windowKeysOn ? "window shortcuts on" : "Rectangle is running: window shortcuts off")
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willLaunchApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                guard Self.bundleID(n) == Self.rectangleID else { return }
                MainActor.assumeIsolated { self?.setWindowKeys(false) }   // before Rectangle claims its keys
            }
        }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard Self.bundleID(n) == Self.rectangleID else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { self?.syncRectangle() } }
        }
    }

    private nonisolated static func bundleID(_ n: Notification) -> String? {
        (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }

    /// Rebind every shortcut from `cfg`; save it when asked (the settings
    /// window saves; loading at launch doesn't).
    func apply(_ cfg: ShortcutConfig, save: Bool) {
        windowKeys.forEach { $0.delete() }
        windowKeys = []
        menuKey?.delete()
        menuKey = nil
        config = cfg
        bindings = derive(cfg)
        if active {
            for b in bindings {
                switch b.owner {
                case .menu:
                    menuKey = HotkeyCenter.shared.register(b.combo) { [weak self] in self?.openMenuAtMouse() }
                    if !suspended { menuKey?.enable() }
                case .action(let a):
                    let wholeApp = b.scope == .app, next = b.nextScreen
                    guard let hk = HotkeyCenter.shared.register(b.combo, { [weak self] in
                        self?.shepherd.doAction(a, wholeApp: wholeApp, nextScreen: next)
                    }) else { continue }
                    if windowKeysOn && !suspended { hk.enable() }
                    windowKeys.append(hk)
                case .screen:
                    break
                }
            }
        }
        syncNumberKeys(force: true)
        if save { store.save(cfg) }
    }

    func syncNumberKeys(force: Bool = false) {
        var n = active ? Screens.destinations(shepherd.system.screens()).count : 0
        if n < 2 { n = 0 }
        guard n != numberKeyCount || force else { return }
        numberKeys.forEach { $0.delete() }
        numberKeys = []
        numberKeyCount = n
        for b in bindings where b.owner == .screen && (b.screen ?? 99) <= n {
            let screen = b.screen!, scope = b.scope
            guard let hk = HotkeyCenter.shared.register(b.combo, { [weak self] in
                self?.shepherd.toNumberedScreen(screen, scope: scope)
            }) else { continue }
            if !suspended { hk.enable() }
            numberKeys.append(hk)
        }
    }

    /// Recording a new shortcut: every key off, then back as it was.
    func suspend(_ on: Bool) {
        suspended = on
        for hk in numberKeys { on ? hk.disable() : hk.enable() }
        if let m = menuKey { on ? m.disable() : m.enable() }
        for hk in windowKeys { (on || !windowKeysOn) ? hk.disable() : hk.enable() }
    }

    private func setWindowKeys(_ on: Bool) {
        guard windowKeysOn != on else { return }
        windowKeysOn = on
        for hk in windowKeys { (on && !suspended) ? hk.enable() : hk.disable() }
        Log.info(on ? "window shortcuts on" : "Rectangle is running: window shortcuts off")
    }

    /// Also run every 2 s as a backstop (cheap: the running-apps list only).
    func syncRectangle() { setWindowKeys(!shepherd.system.isRunning(bundleID: Self.rectangleID)) }

    /// The formatted shortcut for a binding (⌃⌥⌘ key ⇧), or nil if none is bound.
    func keyLabel(_ owner: Owner, _ scope: Scope, next: Bool = false, screen: Int? = nil) -> String? {
        bindings.find(owner, scope, next: next, screen: screen)?.combo.formatted
    }
}
