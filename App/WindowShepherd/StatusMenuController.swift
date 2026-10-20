import AppKit

/// The ⧉ menu-bar item.
@MainActor
final class StatusMenuController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    override init() {
        super.init()
        item.autosaveName = "WindowShepherd"
        item.button?.title = "⧉"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Window Shepherd", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func popUpAtMouse() {
        item.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
