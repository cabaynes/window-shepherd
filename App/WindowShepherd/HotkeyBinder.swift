import AppKit
import WindowShepherdCore

/// Binds every Window Shepherd shortcut from the config. ⌥⌘ + key = this
/// window; add ⌃ = every window of the front app; add ⇧ = on the next
/// screen. Screen keys are bound only for screens that exist (and only with
/// 2+), so apps keep the other numbers. While Rectangle runs, only the keys
/// it also uses switch off; everything else stays on.
@MainActor
final class HotkeyBinder {
    nonisolated static let rectangleID = BackgroundShortcuts.rectangleID

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
    /// The bound shortcuts Rectangle also uses, while it runs (Rectangle gets them).
    private(set) var rectangleShared: [Combo] = []
    /// Every key Rectangle uses while it runs (bound by us or not), by Combo.id.
    private var rectangleKeys: Set<String> = []
    var onRectangleSharedChanged: (([Combo]) -> Void)?
    /// False while Accessibility is missing: nothing is registered.
    var active = false { didSet { if active != oldValue { apply(config, save: false) } } }

    init(shepherd: Shepherd, store: ShortcutStore, openMenuAtMouse: @escaping () -> Void) {
        self.shepherd = shepherd
        self.store = store
        self.openMenuAtMouse = openMenuAtMouse
        config = store.load()
        bindings = derive(config)
        Log.info("window shortcuts on")
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                guard Self.bundleID(n) == Self.rectangleID else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { self?.syncRectangle() } }
            }
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
                    if let m = menuKey, shouldEnable(m) { m.enable() }
                case .action(let a):
                    let wholeApp = b.scope == .app, next = b.nextScreen
                    guard let hk = HotkeyCenter.shared.register(b.combo, { [weak self] in
                        self?.shepherd.doAction(a, wholeApp: wholeApp, nextScreen: next)
                    }) else { continue }
                    if shouldEnable(hk) { hk.enable() }
                    windowKeys.append(hk)
                case .screen:
                    break
                }
            }
        }
        syncNumberKeys(force: true)
        syncRectangle()
        if save { store.save(cfg) }
    }

    /// Re-read the saved shortcuts (after a keyboard layout switch, a key the
    /// old layout lacked may exist now) and rebind.
    func reload() { apply(store.load(), save: false) }

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
            if shouldEnable(hk) { hk.enable() }
            numberKeys.append(hk)
        }
    }

    /// Recording a new shortcut: every key off, then back as it was.
    func suspend(_ on: Bool) {
        suspended = on
        enableAsDecided()
    }

    /// The one rule for every key: on, unless recording or Rectangle has it.
    private func shouldEnable(_ hk: Hotkey) -> Bool {
        !suspended && !rectangleKeys.contains(hk.combo.id)
    }

    private func enableAsDecided() {
        for hk in windowKeys + numberKeys + (menuKey.map { [$0] } ?? []) { shouldEnable(hk) ? hk.enable() : hk.disable() }
    }

    /// Also run every 2 s as a backstop. Cheap: the running-apps list, plus
    /// Rectangle's saved preferences only while it runs.
    func syncRectangle() {
        let running = shepherd.system.isRunning(bundleID: Self.rectangleID)
        let keys: Set<String> = running ? Set(BackgroundShortcuts.rectangleLive().map(\.combo.id)) : []
        if keys != rectangleKeys {
            rectangleKeys = keys
            enableAsDecided()
        }
        let bound = windowKeys + numberKeys + (menuKey.map { [$0] } ?? [])
        let shared = bound.map(\.combo).filter { rectangleKeys.contains($0.id) }
        guard shared.map(\.id).sorted() != rectangleShared.map(\.id).sorted() else { return }
        rectangleShared = shared
        Log.info(shared.isEmpty ? "window shortcuts on"
                 : "Rectangle is running: \(shared.count) shared shortcuts off (\(shared.map(\.formatted).joined(separator: " ")))")
        onRectangleSharedChanged?(shared)
    }

    /// The formatted shortcut for a binding (⌃⌥⌘ key ⇧), or nil if none is bound.
    func keyLabel(_ owner: Owner, _ scope: Scope, next: Bool = false, screen: Int? = nil) -> String? {
        bindings.find(owner, scope, next: next, screen: screen)?.combo.formatted
    }
}
