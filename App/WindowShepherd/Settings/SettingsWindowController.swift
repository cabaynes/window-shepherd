import AppKit
import SwiftUI
import WindowShepherdCore

/// The Customize Shortcuts window. One at a time; closing it drops any
/// pending Keep / Cancel and stops the open-apps check.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: SettingsModel?
    private let target: ShortcutApplying

    init(target: ShortcutApplying) { self.target = target }

    func show() {
        NSApp.activate()
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = SettingsModel(target: target)
        #if DEBUG
        // Development: `-WSSnapshotSettings <png path>` draws the whole window, unscrolled, to a file.
        let snapshot = UserDefaults.standard.string(forKey: "WSSnapshotSettings")
        #else
        let snapshot: String? = nil
        #endif
        let height: CGFloat = snapshot == nil ? 780 : 2600
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: height),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Customize Shortcuts"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SettingsView(model: model, height: height))
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
        self.model = model
        model.opened()
        if let snapshot {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                guard let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: snapshot))
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) { model?.resignedKey() }

    func windowWillClose(_ notification: Notification) {
        model?.closed()
        model = nil
        window = nil
    }
}

extension HotkeyBinder: ShortcutApplying {}
