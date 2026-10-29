import AppKit
import WindowShepherdCore

/// Bridges the Customize Shortcuts window to `SettingsFlow` (the logic), the
/// key recorder and the open-apps scan.
@MainActor
final class SettingsModel: ObservableObject {
    let flow: SettingsFlow
    @Published private(set) var vm: SettingsVM
    @Published private(set) var revision = 0
    /// The connected screens, numbered as the screen keys use them; kept live.
    @Published private(set) var screens = Screens.destinations(Screens.live())
    /// "Windows opened while undocked", saved as soon as it changes.
    @Published private(set) var undocked = UndockedStore().load()
    private let recorder = KeyRecorder()
    private var scan: ScanHandle?
    private var screenWatch: NSObjectProtocol?

    init(target: ShortcutApplying) {
        // Names for changed macOS shortcuts are read once per window; which
        // ones are switched on is asked live (fast, no app calls).
        let names = SystemShortcuts.changedNames()
        let check: ([Combo]) -> [SystemShortcut] = { combos in
            SystemShortcuts.match(combos: combos, enabled: SystemShortcuts.enabled(), changedNames: names)
        }
        flow = SettingsFlow(target: target, systemCheck: check)
        vm = flow.vm
        flow.onChange = { [weak self] in self?.refresh() }
        recorder.onKey = { [weak self] code, flags in self?.key(code, flags) }
        screenWatch = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screens = Screens.destinations(Screens.live()) }
        }
    }

    private func refresh() {
        vm = flow.vm
        revision += 1
        if flow.recording != nil { recorder.start() } else { recorder.stop() }
    }

    private func key(_ code: UInt16, _ flags: CGEventFlags) {
        guard flow.recording != nil else { return }
        if code == 53 {   // Esc, with or without modifiers: cancel
            flow.stopRecording()
            return
        }
        guard let name = KeyCodes.name(for: code) else { return }
        flow.recorded(mods: mods(fromCGFlags: flags), key: name)
    }

    func setUndocked(_ u: UndockedWindows) {
        undocked = u
        UndockedStore().save(u)
    }

    func opened() {
        flow.scanStarted()
        let combos = derive(flow.config).map(\.combo)
        scan = ClashScanner().start(combos: combos, onUpdate: { [weak self] s, done, total in
            self?.flow.scanProgress(s, done: done, total: total)
        }, onDone: { [weak self] s in
            self?.flow.scanFinished(s)
        })
    }

    func closed() {
        scan?.stop()
        scan = nil
        flow.closed()
        recorder.stop()
        if let screenWatch { NotificationCenter.default.removeObserver(screenWatch) }
        screenWatch = nil
    }

    func resignedKey() {
        if flow.recording != nil { flow.stopRecording() }   // switched away: stop catching keys
    }
}
