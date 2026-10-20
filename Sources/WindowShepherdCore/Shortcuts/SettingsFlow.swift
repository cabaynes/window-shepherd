import Foundation

/// Where the settings window applies shortcuts (the app's hotkey binder).
@MainActor
public protocol ShortcutApplying: AnyObject {
    var config: ShortcutConfig { get }
    func apply(_ cfg: ShortcutConfig, save: Bool)
    /// While recording, every Window Shepherd shortcut is off, so pressing one
    /// records it instead of moving a window.
    func suspend(_ on: Bool)
}

/// The Customize Shortcuts window's behaviour, without the UI: recording,
/// red (blocked) and amber (Keep / Cancel) verdicts, and "a change made while
/// the open-apps check runs waits for it". Ported from settings-window.lua.
@MainActor
public final class SettingsFlow {
    public struct Pending: Equatable {
        public let cand: ShortcutConfig
        public let entry: Entry?
        public let warns: [String]
        public let waiting: Bool
        /// The keys being set, for "Keep ⌥⌘U".
        public var keys: String? {
            guard let entry, case let .combo(c) = cand[entry] else { return nil }
            return c.formatted
        }
    }

    public static let allKey = "all"

    private let target: ShortcutApplying
    private let systemCheck: ([Combo]) -> [SystemShortcut]

    public private(set) var recording: Entry?
    public private(set) var recordHint: String?
    public private(set) var pending: Pending?
    /// Entry key (or "all") → why the last change to it was refused.
    public private(set) var errors: [String: String] = [:]
    public private(set) var sources = ClashSources()
    public private(set) var scanning = false
    public private(set) var progress: String?
    public var onChange: (() -> Void)?

    public init(target: ShortcutApplying, systemCheck: @escaping ([Combo]) -> [SystemShortcut]) {
        self.target = target
        self.systemCheck = systemCheck
    }

    public var config: ShortcutConfig { target.config }
    public var vm: SettingsVM { settingsVM(config: target.config, sources: sources, systemCheck: systemCheck) }

    public var statusText: String {
        scanning ? "Checking your open apps for clashes… " + (progress ?? "")
                 : "Checked macOS, your open apps and popular apps."
    }

    // MARK: The open-apps check

    public func scanStarted() {
        scanning = true
        changed()
    }

    public func scanProgress(_ s: ClashSources, done: Int, total: Int) {
        sources = s
        progress = "\(done) of \(total)"
        changed()
    }

    public func scanFinished(_ s: ClashSources) {
        sources = s
        scanning = false
        progress = nil
        if let p = pending, p.waiting {
            pending = nil
            propose(p.cand, p.entry)
        } else {
            changed()
        }
    }

    // MARK: Recording

    public func record(_ entry: Entry) {
        stopRecording()
        pending = nil
        recording = entry
        errors[entry.key] = nil
        target.suspend(true)
        changed()
    }

    public func stopRecording() {
        guard recording != nil else { return }
        recording = nil
        recordHint = nil
        target.suspend(false)
        changed()
    }

    /// A key pressed while recording. Without ⌃, ⌥ or ⌘ it's ignored (keep
    /// listening, like Rectangle), so a shortcut never gets in the way of typing.
    public func recorded(mods: Set<Mod>, key: String) {
        guard let entry = recording else { return }
        guard mods.contains(.ctrl) || mods.contains(.alt) || mods.contains(.cmd) else {
            recordHint = "Hold ⌃, ⌥ or ⌘ too"
            changed()
            return
        }
        stopRecording()
        var cand = target.config
        cand[entry] = .combo(Combo(mods: mods, key: key))
        propose(cand, entry)
    }

    // MARK: Changes

    /// Try a candidate config for `entry` (nil = all). `direct` = a reset:
    /// apply unless blocked, no Keep / Cancel.
    func propose(_ cand: ShortcutConfig, _ entry: Entry?, direct: Bool = false) {
        let key = entry?.key ?? Self.allKey
        errors[key] = nil
        switch judge(candidate: cand, entry: entry, sources: sources, systemCheck: systemCheck) {
        case .blocked(let why):
            errors[key] = why
            pending = nil
        case .ok where scanning && !direct:
            pending = Pending(cand: cand, entry: entry, warns: [], waiting: true)   // decided when the scan is done
        case .ok:
            apply(cand)
        case .warn where direct:
            apply(cand)
        case .warn(let warns):
            pending = Pending(cand: cand, entry: entry, warns: warns, waiting: false)
        }
        changed()
    }

    private func apply(_ cand: ShortcutConfig) {
        target.apply(cand, save: true)
        errors = [:]
        pending = nil
    }

    public func keep() {
        guard let p = pending, !p.waiting else { return }
        apply(p.cand)
        changed()
    }

    public func cancel() {
        pending = nil
        changed()
    }

    public func reset(_ entry: Entry) {
        var cand = target.config
        cand[entry] = ShortcutConfig.defaults[entry]
        propose(cand, entry, direct: true)
    }

    public func resetAll() { propose(.defaults, nil, direct: true) }

    /// The whole-app or next-screen modifier.
    public func setModifier(_ which: Entry, _ m: Mod) {
        var cand = target.config
        cand[which] = .mod(m)
        propose(cand, which)
    }

    public func toggleScreenMod(_ m: Mod) {
        var cand = target.config
        if cand.screenBase.contains(m) { cand.screenBase.remove(m) } else { cand.screenBase.insert(m) }
        propose(cand, .screenBase)
    }

    /// The window closed: a pending Keep / Cancel is dropped, nothing half-applied.
    public func closed() {
        stopRecording()
        pending = nil
    }

    private func changed() { onChange?() }
}
