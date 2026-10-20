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
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 780),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Customize Shortcuts"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SettingsView(model: model))
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
        self.model = model
        model.opened()
    }

    func windowDidResignKey(_ notification: Notification) { model?.resignedKey() }

    func windowWillClose(_ notification: Notification) {
        model?.closed()
        model = nil
        window = nil
    }
}

extension HotkeyBinder: ShortcutApplying {}
