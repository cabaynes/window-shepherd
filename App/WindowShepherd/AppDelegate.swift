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
        statusMenu = StatusMenuController()
        binder = HotkeyBinder(shepherd: shepherd, store: ShortcutStore()) { [weak self] in self?.statusMenu.popUpAtMouse() }
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

    private func tick() {
        shepherd.tick()
        binder.syncRectangle()
        binder.syncNumberKeys()
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
}
