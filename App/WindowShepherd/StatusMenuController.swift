import AppKit
import WindowShepherdCore

/// What the menu needs from the rest of the app.
@MainActor
struct MenuHooks {
    var shepherd: Shepherd
    var binder: () -> HotkeyBinder?
    var launchAtLogin: () -> Bool
    var needsAccess: () -> Bool
    var perform: (MenuAction) -> Void
}

/// The ⧉ menu-bar item. The menu is rebuilt each time it opens, from the
/// fast window list only (instant). Shortcuts are drawn as right-aligned
/// text in ⌃ ⌥ ⌘ key ⇧ order (NSMenu's own key equivalents would put ⇧
/// before ⌘). Reference rows are enabled items so they draw full-strength.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let hooks: MenuHooks
    private var busyShown: Bool?

    init(hooks: MenuHooks) {
        self.hooks = hooks
        super.init()
        item.autosaveName = "WindowShepherd"
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        setBusy(false)
        updateTooltip()
    }

    func setBusy(_ busy: Bool) {
        guard busy != busyShown, let button = item.button else { return }
        busyShown = busy
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = MenuBarGlyph.image(busy: busy)
    }

    func updateTooltip() {
        let key = hooks.binder()?.config.menu.formatted ?? "⌃⌥⌘M"
        item.button?.toolTip = "Move windows between screens (or press \(key) anywhere)"
    }

    /// Opens at the mouse, but moved up (or left) as far as it takes to show
    /// the whole menu: near the bottom of a screen NSMenu would make it scroll.
    func popUpAtMouse() {
        let mouse = NSEvent.mouseLocation
        menuNeedsUpdate(menu)   // build it now, so it can be measured
        var at = mouse          // the menu's top-left corner
        if let vf = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })?.visibleFrame {
            let size = menu.size
            if at.y - size.height < vf.minY { at.y = min(vf.maxY, vf.minY + size.height) }
            if at.x + size.width > vf.maxX { at.x = max(vf.minX, vf.maxX - size.width) }
        }
        menu.popUp(positioning: nil, at: at, in: nil)
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        let s = hooks.shepherd
        let binder = hooks.binder()
        let cfg = binder?.config ?? .defaults
        let inputs = MenuInputs(ctx: s.menuContext(), screens: s.system.screens(), bindings: binder?.bindings ?? derive(cfg),
                                config: cfg, retry: s.retryRows(), launchAtLogin: hooks.launchAtLogin(),
                                needsAccess: hooks.needsAccess(), retryAt: s.retryOffer?.at)
        render(MenuModel.build(inputs), into: menu)
        updateTooltip()
    }

    // MARK: Clicking a row that has a submenu

    // NSMenu ignores a click on a row with a submenu. While the menu is open, a
    // listen-only mouse tap notices one and runs that row's "This window"
    // choice; hovering still opens the submenu as before.
    private var clickTap: CFMachPort?
    private var clickSource: CFRunLoopSource?
    private var mainMenuWindow: NSWindow?

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu, clickTap == nil else { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: CGEventMask(1 << CGEventType.leftMouseUp.rawValue),
                                          callback: { _, type, event, info in
            if type == .leftMouseUp, let info {
                let me = Unmanaged<StatusMenuController>.fromOpaque(info).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { me.mouseUp() } }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: me) else { return }   // no tap: the submenu's "This window" row still works
        clickTap = tap
        clickSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), clickSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu, let tap = clickTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let clickSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), clickSource, .commonModes) }
        CFMachPortInvalidate(tap)
        clickTap = nil
        clickSource = nil
        mainMenuWindow = nil
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if menu === self.menu, item != nil { mainMenuWindow = menuWindow(at: NSEvent.mouseLocation) ?? mainMenuWindow }
    }

    private func mouseUp() {
        guard clickTap != nil,   // the menu already closed: its highlight is stale
              let row = menu.highlightedItem, let sub = row.submenu, let box = row.representedObject as? ActionBox,
              sub.highlightedItem == nil else { return }   // on a submenu row: that row's own click runs it
        // Over the submenu (a separator, its edge)? Only a click on the main menu counts.
        if let here = menuWindow(at: NSEvent.mouseLocation), let main = mainMenuWindow, here !== main { return }
        menu.cancelTracking()
        DispatchQueue.main.async { [hooks] in hooks.perform(box.action) }
    }

    private func menuWindow(at p: NSPoint) -> NSWindow? {
        NSApp.windows.filter { $0.isVisible && $0.frame.contains(p) && $0.level >= .popUpMenu }.max { $0.level < $1.level }
    }

    // MARK: Rendering

    private final class ActionBox: NSObject {
        let action: MenuAction
        init(_ a: MenuAction) { action = a }
    }

    private func render(_ nodes: [MenuNode], into menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let font = NSFont.menuFont(ofSize: 0)
        // Right tab stop for the keys, past the widest title in this menu.
        let widest = nodes.map { node -> CGFloat in
            switch node {
            case let .item(t, _, _, _), let .submenu(t, _, _): return (t as NSString).size(withAttributes: [.font: font]).width
            default: return 0
            }
        }.max() ?? 0
        let keysWidth = nodes.map { node -> CGFloat in
            switch node {
            case let .item(_, k?, _, _), let .submenu(_, k?, _): return (k as NSString).size(withAttributes: [.font: font]).width
            default: return 0
            }
        }.max() ?? 0
        let tabAt = widest + 40 + keysWidth
        // Left tab stop for reference rows (keys first, then what they do).
        let refKeysWidth = nodes.map { node -> CGFloat in
            if case let .reference(k, _) = node { return (k as NSString).size(withAttributes: [.font: font]).width }
            return 0
        }.max() ?? 0

        var lastWasSeparator = true
        for node in nodes {
            switch node {
            case .separator:
                if !lastWasSeparator { menu.addItem(.separator()) }
                lastWasSeparator = true
                continue
            case let .item(title, keys, action, indent):
                let mi = NSMenuItem(title: title, action: #selector(clicked(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = ActionBox(action)
                mi.indentationLevel = indent
                if let keys { mi.attributedTitle = withKeys(title, keys, tabAt: tabAt, font: font) }
                menu.addItem(mi)
            case let .submenu(title, keys, children):
                let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                if let keys { mi.attributedTitle = withKeys(title, keys, tabAt: tabAt, font: font) }
                // Clicking the row itself does its "This window" choice (see ClickThrough).
                if case let .item(first, _, action, _)? = children.first, first.hasPrefix("This window") {
                    mi.representedObject = ActionBox(action)
                }
                let sub = NSMenu(title: title)
                render(children, into: sub)
                mi.submenu = sub
                menu.addItem(mi)
            case let .toggle(title, on, action):
                let mi = NSMenuItem(title: title, action: #selector(clicked(_:)), keyEquivalent: "")
                mi.target = self
                mi.state = on ? .on : .off
                mi.representedObject = ActionBox(action)
                menu.addItem(mi)
            case let .header(title):
                let mi = NSMenuItem(title: title, action: #selector(noop(_:)), keyEquivalent: "")
                mi.target = self
                mi.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
                menu.addItem(mi)
            case let .reference(keys, what):
                let mi = NSMenuItem(title: keys + "  " + what, action: #selector(noop(_:)), keyEquivalent: "")
                mi.target = self
                let para = NSMutableParagraphStyle()
                para.tabStops = [NSTextTab(textAlignment: .left, location: refKeysWidth + 24)]
                mi.attributedTitle = NSAttributedString(string: keys + "\t" + what,
                                                        attributes: [.font: font, .paragraphStyle: para])
                menu.addItem(mi)
            }
            lastWasSeparator = false
        }
        if let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
        if menu === self.menu, let quit = menu.items.last, quit.title == "Quit Window Shepherd" {
            quit.keyEquivalent = "q"
            quit.keyEquivalentModifierMask = .command
        }
    }

    private func withKeys(_ title: String, _ keys: String, tabAt: CGFloat, font: NSFont) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .right, location: tabAt)]
        let s = NSMutableAttributedString(string: title + "\t" + keys, attributes: [.font: font, .paragraphStyle: para])
        return s
    }

    @objc private func clicked(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ActionBox else { return }
        hooks.perform(box.action)
    }

    @objc private func noop(_ sender: NSMenuItem) {}
}
