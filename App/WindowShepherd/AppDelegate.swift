import AppKit
import Carbon.HIToolbox
import WindowShepherdCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var shepherd: Shepherd!
    private(set) var binder: HotkeyBinder!
    private var statusMenu: StatusMenuController!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("Window Shepherd \(Bundle.main.shortVersion) started")
        shepherd = Shepherd(system: LiveWindowSystem(), store: LayoutStore())
        statusMenu = StatusMenuController(hooks: MenuHooks(
            shepherd: shepherd,
            binder: { [weak self] in self?.binder },
            launchAtLogin: { false },
            needsAccess: { false },
            perform: { [weak self] in self?.perform($0) }))
        binder = HotkeyBinder(shepherd: shepherd, store: ShortcutStore()) { [weak self] in self?.statusMenu.popUpAtMouse() }
        shepherd.onAlert = { HUD.show($0) }
        shepherd.onBusyChanged = { [weak self] in self?.statusMenu.setBusy($0) }
        shepherd.start()
        binder.active = true

        // The one cheap poll (fast window list, running apps): screen setup
        // changes, the Rectangle backstop, and number keys for new screens.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.shepherd.screensChanged() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                KeyCodes.reload()
                guard let self else { return }
                self.binder.apply(self.binder.config, save: false)
            }
        }
    }

    private func perform(_ action: MenuAction) {
        switch action {
        case .apply, .moveTo:
            switch MenuModel.resolve(action, screens: shepherd.system.screens()) {
            case let .run(sel, placer, label)?: shepherd.apply(sel, placer: placer, label: label)
            case let .refused(msg)?: HUD.show(msg)
            case nil: break
            }
        case .retry: shepherd.runRetry()
        case .quit: NSApp.terminate(nil)
        case .customize, .noop, .launchAtLogin, .about, .checkForUpdates, .grantAccess: break
        }
    }

    private func tick() {
        shepherd.tick()
        binder.syncRectangle()
        binder.syncNumberKeys()
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
}
