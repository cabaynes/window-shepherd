import AppKit
import Carbon.HIToolbox
import SwiftUI
import WindowShepherdCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var shepherd: Shepherd!
    private(set) var binder: HotkeyBinder!
    private var statusMenu: StatusMenuController!
    private var timer: Timer?
    private var settings: SettingsWindowController?
    private let permission = PermissionWatcher()
    private var onboardingWindow: NSWindow?
    private var onboarding: OnboardingModel?
    private var updater: Updater!

    /// Posted with object "1" / "0" when Window Shepherd starts or stops
    /// moving windows, so the Hammerspoon window mover can step aside only
    /// while this app actually works (it has the Accessibility permission).
    static let activeNotification = Notification.Name("com.windowshepherd.WindowShepherd.active")
    static let queryNotification = Notification.Name("com.windowshepherd.WindowShepherd.query")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("Window Shepherd \(Bundle.main.shortVersion) started")
        updater = Updater()
        shepherd = Shepherd(system: LiveWindowSystem(), store: LayoutStore())
        statusMenu = StatusMenuController(hooks: MenuHooks(
            shepherd: shepherd,
            binder: { [weak self] in self?.binder },
            launchAtLogin: { LaunchAtLogin.isEnabled },
            needsAccess: { [weak self] in !(self?.permission.isTrusted ?? true) },
            perform: { [weak self] in self?.perform($0) }))
        binder = HotkeyBinder(shepherd: shepherd, store: ShortcutStore()) { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.statusMenu.popUpAtMouse() } }
        }
        shepherd.onAlert = { HUD.show($0) }
        shepherd.onBusyChanged = { [weak self] in self?.statusMenu.setBusy($0) }

        permission.onChange = { [weak self] trusted in self?.permissionChanged(trusted) }
        if permission.isTrusted {
            activate()
        } else {
            shepherd.paused = true
            Log.info("waiting for the Accessibility permission")
            showOnboarding()
        }

        // The one cheap poll (fast window list, running apps): screen setup
        // changes, the Rectangle backstop, and number keys for new screens.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.shepherd.screensChanged() }
        }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                KeyCodes.reload()
                guard let self else { return }
                // Re-read the saved shortcuts: a key the old layout lacked may exist now.
                self.binder.reload()
            }
        }
        dnc.addObserver(forName: Self.queryNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.announce() }
        }
        #if DEBUG
        // Development: `open "Window Shepherd.app" --args -WSOpenSettings YES` opens Customize Shortcuts.
        if UserDefaults.standard.bool(forKey: "WSOpenSettings") { perform(.customize) }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().postNotificationName(Self.activeNotification, object: "0",
                                                                     userInfo: nil, deliverImmediately: true)
    }

    /// Start moving windows: the engine, hotkeys, and tell Hammerspoon.
    private func activate() {
        shepherd.paused = false
        shepherd.start()
        binder.active = true
        announce()
        #if !DEBUG
        // On by default: the first time the app runs with the permission and no
        // onboarding window is asking, switch Launch at Login on (once).
        if !LaunchAtLogin.decided && onboardingWindow == nil { LaunchAtLogin.set(true) }
        #endif
    }

    private func announce() {
        let active = permission.isTrusted && binder.active
        DistributedNotificationCenter.default().postNotificationName(Self.activeNotification, object: active ? "1" : "0",
                                                                     userInfo: nil, deliverImmediately: true)
    }

    private func permissionChanged(_ trusted: Bool) {
        Log.info(trusted ? "Accessibility permission granted" : "Accessibility permission removed")
        if trusted {
            activate()
            onboarding?.granted = true
            NSApp.activate()
            onboardingWindow?.makeKeyAndOrderFront(nil)
        } else {
            shepherd.paused = true
            binder.active = false
            announce()
        }
    }

    // MARK: Onboarding

    private func showOnboarding() {
        NSApp.activate()
        if let w = onboardingWindow {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let model = OnboardingModel()
        model.granted = permission.isTrusted
        model.onDone = { [weak self] in self?.finishOnboarding() }
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Welcome to Window Shepherd"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: OnboardingView(model: model))
        w.setContentSize(w.contentView!.fittingSize)
        w.center()
        w.makeKeyAndOrderFront(nil)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Closing "You're all set" counts like Done: apply what the checkbox shows.
                if let model = self?.onboarding, model.granted { self?.applyLoginChoice(model) }
                self?.permission.pollWhileVisible(false)
                self?.onboardingWindow = nil
                self?.onboarding = nil
            }
        }
        onboardingWindow = w
        onboarding = model
        permission.pollWhileVisible(true)
    }

    private func finishOnboarding() {
        onboardingWindow?.close()   // the close handler applies the login choice
    }

    private func applyLoginChoice(_ model: OnboardingModel) {
        if model.launchAtLogin != LaunchAtLogin.isEnabled { LaunchAtLogin.set(model.launchAtLogin) }
        LaunchAtLogin.decided = true
    }

    // MARK: Menu actions

    private func perform(_ action: MenuAction) {
        switch action {
        case .apply, .moveTo:
            switch MenuModel.resolve(action, screens: shepherd.system.screens()) {
            case let .run(sel, placer, label)?: shepherd.apply(sel, placer: placer, label: label)
            case let .refused(msg)?: HUD.show(msg)
            case nil: break
            }
        case .retry(let at): shepherd.runRetry(offerAt: at)
        case .customize:
            if settings == nil { settings = SettingsWindowController(target: binder) }
            settings?.show()
        case .launchAtLogin: LaunchAtLogin.toggle()
        case .about: AboutPanel.show()
        case .checkForUpdates: updater.checkForUpdates()
        case .grantAccess: showOnboarding()
        case .quit: NSApp.terminate(nil)
        case .noop: break
        }
    }

    private func tick() {
        permission.check()
        shepherd.tick()
        binder.syncRectangle()
        binder.syncNumberKeys()
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
}
